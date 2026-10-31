"""Run one isolated ModelSim check; reports include source hashes and scenarios."""
from pathlib import Path
import argparse
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CHECKS = {
    'unit': ('bmp_downscale', 'bmp_downscale', 600),
    'writeback': ('bmp_downscale_writeback', 'bmp_downscale_writeback', 180),
    'legacy': ('bmp_capacity', 'bmp_capacity', 180),
    'catalog': ('catalog_matrix', 'catalog_matrix', 180),
    'system': ('downscale_integration', 'integration', 1500),
    'board': ('board_compile', None, 180),
    'fft_init': ('layer_fft64', 'layer_fft64', 120),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('check', choices=CHECKS)
    parser.add_argument('--compile-only', action='store_true')
    parser.add_argument('--suffix', default='r1')
    args = parser.parse_args()
    config, expected, timeout = CHECKS[args.check]
    env = os.environ.copy()
    env.update(SIMULATOR='modelsim', MODELSIM_CONFIG=f'sim/modelsim_{config}.json',
               SIM_OUTPUT=f'downscale_{args.check}_{args.suffix}', ENABLE_VCD='0',
               RUN_SIM='0' if args.compile_only or expected is None else '1',
               TIMEOUT_SECONDS=str(timeout))
    env.setdefault('ICCODER_VSIM', r'D:\modeltech64_10.6e\win64\vsim.exe')
    if expected:
        env['EXPECTED_SCENARIOS'] = f'tb/expected_{expected}.json'
    return subprocess.call([sys.executable, 'sim/run.py'], cwd=ROOT, env=env)


if __name__ == '__main__':
    raise SystemExit(main())
