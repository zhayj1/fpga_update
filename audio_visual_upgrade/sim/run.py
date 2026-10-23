#!/usr/bin/env python3
"""Copy to sim/run.py; invoke from the FPGA project root. Python 3 stdlib only."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


def verdict(log, expected):
    """Require complete, unique, ordered evidence; a clean exit is insufficient."""
    lines = [line.strip() for line in log.splitlines()]
    if any(re.match(r"^(TEST_FAIL|FAIL|ERROR|FATAL|TIMEOUT)\b", line, re.I) or
           re.search(r"\b(?:ERROR|FATAL):", line) for line in lines):
        return False, "Failure diagnostic in simulation log"
    passed = [line.split(maxsplit=1)[1] for line in lines if line.startswith("SCENARIO_PASS ")]
    if len(passed) != len(set(passed)) or set(passed) != set(expected):
        return False, "Missing, duplicate, or unexpected scenario results"
    if lines.count("TEST_PASS") != 1:
        return False, "Exactly one final TEST_PASS is required"
    final = lines.index("TEST_PASS")
    if any(line.startswith("SCENARIO_PASS ") for line in lines[final + 1:]):
        return False, "TEST_PASS occurred before scenario completion"
    return True, "All planned scenarios passed"


def resolve_tool(name):
    override = os.environ.get("ICCODER_" + name.upper())
    if override:
        candidate = Path(override)
        if candidate.is_file():
            return str(candidate.resolve())
        raise FileNotFoundError("Invalid tool override: " + name)
    found = shutil.which(name)
    if found:
        return found
    root = os.environ.get("ICCODER_TOOLS_ROOT")
    if root:
        for suffix in ("", ".exe"):
            candidate = Path(root) / "bin" / (name + suffix)
            if candidate.is_file():
                return str(candidate.resolve())
    raise FileNotFoundError("Tool unavailable: " + name)


def fingerprint(root):
    # Include HDL headers, data images, checkers, source lists and runner settings.
    included = {".v", ".vh", ".sv", ".svh", ".vhd", ".vhdl", ".mem", ".hex", ".json", ".py"}
    paths = []
    for folder in ("rtl", "tb"):
        base = root / folder
        if base.exists():
            paths.extend(p for p in base.rglob("*") if p.is_file() and p.suffix.lower() in included)
    paths.extend(p for p in (root / "sim/sources.f", root / "sim/run.py", root / "sim/run.sh") if p.is_file())
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(set(paths))}


def execute(command, log_path, timeout):
    # File redirection avoids retaining an unbounded simulator log in memory.
    with log_path.open("w", encoding="utf-8") as stream:
        try:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            return result.returncode, False
        except subprocess.TimeoutExpired:
            stream.write("\nTIMEOUT runner wall-clock limit exceeded\n")
            return 124, True


def run(root=None):
    root = Path(root or Path.cwd()).resolve()
    previous = Path.cwd()
    os.chdir(root)
    sim = root / "sim"
    sim.mkdir(exist_ok=True)
    result_path = sim / "sim_result.json"
    result = {
        "status": "ERROR", "reason": "Run did not finish", "started_at": time.time(),
        "compile_exit_code": None, "sim_exit_code": None, "vcd_generated": False,
        "had_compile_fail": False, "first_fail_compile_log": None,
        "vcd_path": None, "compile_log": "sim/compile.log", "sim_log": None,
    }
    # Replace old PASS immediately, including on setup failure.
    result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    exit_code = 2
    try:
        result["input_hashes"] = fingerprint(root)
        wave = os.environ.get("ENABLE_VCD", "0") == "1"
        simulate = os.environ.get("RUN_SIM", "0") == "1" or wave
        timeout = float(os.environ.get("TIMEOUT_SECONDS", "120"))
        if not 0 < timeout < float("inf"):
            raise ValueError("TIMEOUT_SECONDS must be finite and positive")
        top = os.environ.get("TB_TOP_MODULE", "tb_top")
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", top):
            raise ValueError("Invalid TB_TOP_MODULE")
        sources = root / "sim/sources.f"
        if not sources.is_file() or not sources.read_text(encoding="utf-8").strip():
            raise ValueError("Missing or empty sim/sources.f; create the actual dependency list")
        expected = []
        if simulate:
            expected = json.loads((root / "tb/expected_scenarios.json").read_text(encoding="utf-8"))
            if (not isinstance(expected, list) or not expected
                    or any(not isinstance(x, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", x) for x in expected)
                    or len(set(expected)) != len(expected)):
                raise ValueError("Expected scenarios must be nonempty, unique scenario IDs")
        result["expected_scenarios"] = expected
        compiler = resolve_tool("iverilog")
        runtime = resolve_tool("vvp") if simulate else None
        result.update(iverilog=compiler, vvp=runtime, tb_top=top)
        versions = {}
        for name, tool in (("iverilog", compiler), ("vvp", runtime)):
            if tool:
                version = subprocess.run([tool, "-V"], capture_output=True, text=True, errors="replace", timeout=10)
                versions[name] = (version.stdout + version.stderr).strip()
        result["tool_versions"] = versions
        binary = sim / (top + ".vvp")
        command = [compiler, "-g" + os.environ.get("IVERILOG_STANDARD", "2001"), "-Wall", "-s", top, "-f", "sim/sources.f"]
        dut = os.environ.get("DUT_TOP_MODULE")
        if dut:
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", dut):
                raise ValueError("Invalid DUT_TOP_MODULE")
            command.append("-DDUT_MODULE=" + dut)
        command += ["-o", str(binary)] if simulate else ["-tnull"]
        result.update(command=command, timeout_seconds=timeout)
        result["compile_exit_code"], timed_out = execute(command, sim / "compile.log", timeout)
        if result["compile_exit_code"] != 0:
            shutil.copyfile(sim / "compile.log", sim / "compile.fail.log")
            result.update(status="COMPILE_FAIL", had_compile_fail=True,
                          first_fail_compile_log="sim/compile.fail.log",
                          reason="Compile timeout" if timed_out else "Compilation failed")
            exit_code = 1
        elif not simulate:
            result.update(status="COMPILE_PASS", reason="Compile only; simulation not executed")
            exit_code = 0
        else:
            vcd = sim / "wave.vcd"
            if wave and vcd.exists():
                # Only the exact generated waveform owned by this run is replaced.
                vcd.unlink()
            sim_command = [runtime, str(binary)]
            if wave:
                sim_command.append("+VCD=sim/wave.vcd")
            result.update(sim_command=sim_command, sim_log="sim/sim.log")
            result["sim_exit_code"], timed_out = execute(sim_command, sim / "sim.log", timeout)
            log = (sim / "sim.log").read_text(encoding="utf-8", errors="replace")
            passed, reason = verdict(log, expected)
            if result["sim_exit_code"] != 0:
                passed, reason = False, "Simulation timeout" if timed_out else "Simulator returned nonzero"
            generated = wave and vcd.is_file() and vcd.stat().st_size > 0
            if wave and not generated:
                passed, reason = False, "Requested waveform missing or empty for this run"
            result.update(status="PASS" if passed else "FAIL", reason=reason,
                          vcd_generated=generated, vcd_path="sim/wave.vcd" if generated else None)
            exit_code = 0 if passed else 1
        if result["status"] in ("PASS", "COMPILE_PASS") and fingerprint(root) != result["input_hashes"]:
            result.update(status="FAIL", reason="Inputs changed during execution; rerun current sources")
            exit_code = 1
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        result.update(status="ERROR", reason=str(error))
    finally:
        result["finished_at"] = time.time()
        result_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
        os.chdir(previous)
    print(result["status"] + ": " + result["reason"])
    return exit_code


if __name__ == "__main__":
    backend = os.environ.get("SIMULATOR", "modelsim").lower()
    if backend == "modelsim":
        from modelsim_run import run as modelsim_run
        raise SystemExit(modelsim_run())
    if backend == "iverilog":
        raise SystemExit(run())
    raise SystemExit("Unsupported SIMULATOR: " + backend)
