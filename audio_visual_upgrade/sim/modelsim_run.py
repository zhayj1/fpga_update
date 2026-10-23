"""Copy alongside sim/run.py. Isolated ModelSim compilation and self-check runner."""
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid


def quote(value):
    """One Tcl word, with all substitution disabled even in user supplied paths."""
    text = str(value)
    for old, new in (("\\", "\\\\"), ('"', '\\"'), ("$", "\\$"), ("[", "\\["), ("]", "\\]"), ("\n", "\\n"), ("\r", "\\r")):
        text = text.replace(old, new)
    return '"' + text + '"'


def command(*words):
    return " ".join(quote(word) for word in words)


def normal_log(text):
    # ModelSim prefixes tool and HDL output with '# '. Avoid matching echoed Tcl.
    return "\n".join(re.sub(r"^\s*#\s?", "", line) for line in text.splitlines())


def prepare(config, root):
    ident = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
    groups, inputs, libraries = [], set(), []
    def path(value):
        expanded = os.path.expandvars(value)
        if re.search(r"\$\{?\w+", expanded):
            raise ValueError("Unresolved path variable: " + value)
        p = Path(expanded)
        return p if p.is_absolute() else root / p
    for group in config["libraries"]:
        name = group["name"]
        if not ident.fullmatch(name) or name in libraries:
            raise ValueError("Invalid or duplicate library: " + name)
        libraries.append(name)
        sources = []
        for entry in group["sources"]:
            language = entry["language"]
            if language not in ("verilog", "systemverilog", "vhdl"):
                raise ValueError("Unsupported HDL language")
            source_path = path(entry["path"])
            matches = [str(source_path)] if source_path.is_file() else sorted(glob.glob(str(source_path)))
            if not matches:
                raise ValueError("Source not found: " + entry["path"])
            for match in matches:
                p = Path(match).resolve()
                if p.name in ("top_skeleton.v", "top_skeleton.sv") or not p.is_file():
                    raise ValueError("Invalid implementation source: " + str(p))
                inputs.add(p)
                sources.append((language, p))
        if not sources:
            raise ValueError("Empty source library: " + name)
        includes = [path(p).resolve() for p in group.get("include_dirs", [])]
        for p in includes:
            if not p.is_dir():
                raise ValueError("Include directory not found: " + str(p))
            inputs.update(f for f in p.rglob("*") if f.is_file() and f.suffix.lower() in
                          (".v", ".vh", ".sv", ".svh", ".vhd", ".vhdl", ".mem", ".hex"))
        groups.append((name, sources, includes, group.get("defines", [])))
    if not groups:
        raise ValueError("No libraries configured")
    for item in config.get("data_files", []):
        data_path = path(item)
        matches = [data_path.resolve()] if data_path.is_file() else [Path(p).resolve() for p in glob.glob(str(data_path))]
        if not matches or any(not p.is_file() for p in matches):
            raise ValueError("Missing model data: " + item)
        inputs.update(matches)
    for key in ("dut_top", "tb_top"):
        if key in config and not re.fullmatch(r"[A-Za-z_][\w]*\.[A-Za-z_][\w$]*", config[key]):
            raise ValueError("Use library.module for " + key)
        if key in config and config[key].split(".")[0] not in libraries:
            raise ValueError("Top library not compiled: " + config[key])
    return groups, inputs, libraries


def run(root=None):
    # Reuse the common strict scenario checks without changing the legacy backend.
    from run import verdict
    root = Path(root or Path.cwd()).resolve()
    sim = root / "sim"
    sim.mkdir(exist_ok=True)
    output_prefix = os.environ.get("SIM_OUTPUT", "")
    if output_prefix and not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", output_prefix):
        raise ValueError("Invalid SIM_OUTPUT")
    output_prefix = output_prefix + "_" if output_prefix else ""
    result_path = sim / (output_prefix + "sim_result.json")
    result = dict(status="ERROR", reason="Run not finished", backend="modelsim",
                  started_at=time.time(), compile_exit_code=None, sim_exit_code=None,
                  vcd_generated=False, vcd_path=None)
    result_path.write_text(json.dumps(result), encoding="utf-8")
    # Invalidate old convenience logs even if setup fails before ModelSim starts.
    for name in ("compile.log", "sim.log"):
        (sim / (output_prefix + name)).write_text("", encoding="utf-8")
    rc = 2
    try:
        profile = os.environ.get("MODELSIM_PROFILE", "music")
        if profile not in ("music", "twosong", "twosong_distinct"):
            raise ValueError("Unsupported ModelSim profile: " + profile)
        config_path = root / os.environ.get("MODELSIM_CONFIG", "sim/modelsim.json")
        config = json.loads(config_path.read_text(encoding="utf-8"))
        if profile in ("twosong", "twosong_distinct"):
            config["libraries"][0]["defines"].append("TWOSONG")
            if profile == "twosong_distinct":
                config["libraries"][0]["defines"].append("TWOSONG_DISTINCT")
            config["data_files"].append("sim/fat32_" + profile + ".mem")
        groups, inputs, libraries = prepare(config, root)
        wave = os.environ.get("ENABLE_VCD", "0") == "1"
        simulate = os.environ.get("RUN_SIM", "0") == "1" or wave
        timeout = float(os.environ.get("TIMEOUT_SECONDS", "120"))
        if not 0 < timeout < float("inf"):
            raise ValueError("Timeout must be finite and positive")
        dut = config["dut_top"]
        tb = config.get("tb_top")
        if simulate and not tb:
            raise ValueError("Missing tb_top")
        expected = []
        if simulate:
            expected_path = root / os.environ.get("EXPECTED_SCENARIOS", ("tb/expected_scenarios_twosong_distinct.json" if profile == "twosong_distinct"
                                    else "tb/expected_scenarios_twosong.json" if profile == "twosong"
                                    else "tb/expected_scenarios.json"))
            expected = json.loads(expected_path.read_text(encoding="utf-8"))
            if (not isinstance(expected, list) or not expected
                    or any(not isinstance(x, str) or not re.fullmatch(r"[\w.-]+", x, re.ASCII) for x in expected)
                    or len(set(expected)) != len(expected)):
                raise ValueError("Invalid expected_scenarios.json")
        vsim = os.environ.get("ICCODER_VSIM") or shutil.which("vsim")
        if not vsim or not Path(vsim).is_file():
            raise FileNotFoundError("ModelSim unavailable: set ICCODER_VSIM or PATH")
        version = subprocess.run([vsim, "-version"], capture_output=True, text=True, errors="replace", timeout=10)
        result.update(tool_version=(version.stdout + version.stderr).strip(), config=config,
                      expected_scenarios=expected, timeout_seconds=timeout)
        inputs.update((config_path, Path(__file__).resolve(), sim / "run.py"))
        if simulate:
            inputs.add(expected_path)
        def hashes():
            return {p.as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs)}
        result["input_hashes"] = hashes()
        session = sim / "modelsim" / uuid.uuid4().hex
        session.mkdir(parents=True)
        ini = session / "modelsim.ini"
        compile_log, sim_log = sim / (output_prefix + "compile.log"), sim / (output_prefix + "sim.log")
        vcd = session / "wave.vcd"
        lines = ["onerror {quit -code 2 -force}", "onbreak {resume}", "vmap -c",
                 command("transcript", "file", compile_log.as_posix())]
        for name in libraries:
            libpath = (session / name).as_posix()
            lines += [command("vlib", libpath), command("vmap", "-modelsimini", ini.as_posix(), name, libpath)]
        for name, sources, includes, defines in groups:
            for language, src in sources:
                tool = "vcom" if language == "vhdl" else "vlog"
                args = [tool, "-modelsimini", ini.as_posix(), "-work", name]
                args += ["-2008"] if language == "vhdl" else (["-sv"] if language == "systemverilog" else [])
                if language != "vhdl":
                    args += ["+incdir+" + p.as_posix() for p in includes]
                    args += ["+define+" + d for d in defines]
                lines.append(command(*args, src.as_posix()))
        # Load from project root so relative $readmemh/model input paths retain meaning.
        lines.append(command("cd", root.as_posix()))
        load = ["vsim", "-modelsimini", ini.as_posix(), "-onfinish", "stop", "-novopt",
                "+notimingchecks"]
        # ★ 本工程适配（唯一一处改动，2026-10-01）：加 "-novopt" 与 "+notimingchecks"。
        #   ① -novopt：真 SDRAM 栈含厂商**保护模型** ip/sdram/sdr_as_ram.enc.v（IEEE-1735 加密，
        #      带 Mentor 密钥块）。vlog 编得过，但默认 vopt 优化会在保护区域报
        #      `sdr_as_ram.enc.v(103): in protected region` ⇒ 设计装载失败。
        #   ② +notimingchecks：厂商**器件模型** sim/vendor/IS42s32200.v 自带时序检查，
        #      其 tCK 下限是 7ns（143MHz 档），而本设计 `clk_sdr` = 150MHz（6.67ns）
        #      ⇒ 每拍报 `$period` 违规（**是模型速度等级与本板配置不符，不是设计违规**）。
        #   两条都只影响"怎么跑仿真"，**不放松任何验收判据**（场景完整性/退出码/超时/自检门槛不变）。
        for name in libraries:
            load += ["-L", name]
        auxiliaries = config.get("auxiliary_tops", [])
        # DUT can have parameters distinct from TB generic overrides.
        for top, parameters in ((dut, config.get("dut_parameters", {})), (tb, config.get("tb_parameters", {}))):
            if top:
                args = load + ["-g" + key + "=" + str(value) for key, value in parameters.items()] + [top] + auxiliaries
                lines += [command(*args), "quit -sim"]
        lines.append('puts "ICCODER_COMPILE_PASS"')
        if simulate:
            args = load + ["-g" + key + "=" + str(value) for key, value in config.get("tb_parameters", {}).items()] + [tb] + auxiliaries
            if wave:
                args.append("+VCD=" + vcd.as_posix())
            lines += [command("transcript", "file", sim_log.as_posix()), command(*args), "run -all"]
        lines.append("quit -code 0 -force")
        do_file = session / "run.do"
        do_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
        batch = [vsim, "-c", "-do", "do " + quote(do_file.as_posix())]
        result.update(command=batch, script=do_file.relative_to(root).as_posix(),
                      compile_log=compile_log.relative_to(root).as_posix(),
                      sim_log=sim_log.relative_to(root).as_posix() if simulate else None)
        console = session / "console.log"
        with console.open("w", encoding="utf-8") as output:
            try:
                process = subprocess.run(batch, cwd=session, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
                exit_code = process.returncode
            except subprocess.TimeoutExpired:
                exit_code = 124
                output.write("\nTIMEOUT ModelSim wall-clock limit\n")
        raw = console.read_text(encoding="utf-8", errors="replace")
        clean = normal_log(raw)
        compiled = "ICCODER_COMPILE_PASS" in clean.splitlines()
        result.update(batch_exit_code=exit_code, compile_exit_code=0 if compiled else exit_code or 1,
                      sim_exit_code=exit_code if simulate and compiled else None,
                      warning_lines=[line for line in clean.splitlines() if "** Warning:" in line])
        ok, reason = (verdict(clean, expected) if simulate else (compiled, "Compile and elaboration complete; no run executed"))
        if not compiled:
            ok, reason = False, "Compilation/elaboration completion evidence missing"
        if re.search(r"^\*\*\s+(?:Error|Fatal)\b", clean, re.M):
            ok, reason = False, "ModelSim error diagnostic"
        if exit_code:
            ok, reason = False, "ModelSim timeout" if exit_code == 124 else "ModelSim returned nonzero"
        if wave and not (vcd.is_file() and vcd.stat().st_size):
            ok, reason = False, "Requested waveform missing or empty"
        if hashes() != result["input_hashes"]:
            ok, reason = False, "Inputs changed during execution"
        if ok and wave:
            result.update(vcd_generated=True, vcd_path=vcd.relative_to(root).as_posix())
        result.update(status=("PASS" if simulate else "COMPILE_PASS") if ok else ("FAIL" if compiled else "COMPILE_FAIL"), reason=reason)
        rc = 0 if ok else 1
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        result.update(status="ERROR", reason=str(error))
    finally:
        result["finished_at"] = time.time()
        result_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(result["status"] + ": " + result["reason"])
    return rc
