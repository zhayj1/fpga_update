from pathlib import Path
import os, sys, subprocess, json, argparse
parser = argparse.ArgumentParser()
parser.add_argument('--tag', default='display_floor_20261102_r3')
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'output/display_floor_20261102_r1'
base = ['rtl/audio/spec_bands64.v','rtl/audio/spec_attack18.v',
        'output/display_floor_20261102_r1/spec_bands64_original.v','tb/tb_display_floor.v']
scenarios = {
    'floor': ['floor_all_256_codes_and_boundaries','mixed_bins_and_original_smoothing',
              'history_decays_to_zero','reset_restores_silence','original_attack_outputs_cycle_identical'],
    'wav': ['actual_wav_187p5_first_bar_stable_within_2_levels','actual_wav_other_62_bars_zero','actual_wav_original_attack_preserved']}
for key in ['floor','wav','attack_bands','spectrum_stage1','layer_fft64','split_spectrum','split_core','circular_system','circular_board']:
    prefix = args.tag+'_'+key
    assert not (ROOT/'sim'/(prefix+'_sim_result.json')).exists(), 'Preserve '+prefix
    if key in scenarios:
        files = base + (['rtl/audio/spec_window.v','rtl/audio/spec_fft.v','tb/tb_display_floor_wav.v'] if key=='wav' else [])
        config = {'dut_top':'work.spec_bands64','tb_top':'work.tb_display_floor'+('_wav' if key=='wav' else ''),
                  'libraries':[{'name':'work','sources':[{'path':p,'language':'verilog'} for p in files]}]}
        if key=='wav': config['data_files']=['output/display_floor_20261102_r1/tone_left_12bit.hex']
        config_path = OUT/('modelsim_'+key+'.json')
        expected_path = OUT/('expected_'+key+'.json')
        config_path.write_text(json.dumps(config,indent=2),encoding='utf-8')
        expected_path.write_text(json.dumps(scenarios[key]),encoding='utf-8')
    else:
        config_path=ROOT/'sim'/('modelsim_'+key+'.json')
        expected_path=ROOT/'tb'/('expected_'+('integration' if key=='circular_system' else key)+'.json')
    env=os.environ.copy()
    env.update(SIMULATOR='modelsim',MODELSIM_CONFIG=str(config_path),SIM_OUTPUT=prefix,
               ENABLE_VCD='0',TIMEOUT_SECONDS='1200',RUN_SIM='0' if key=='circular_board' else '1',
               ICCODER_VSIM=r'D:\modeltech64_10.6e\win64\vsim.exe',EXPECTED_SCENARIOS=str(expected_path))
    print('Checking '+key,flush=True)
    rc=subprocess.call([sys.executable,'-B','sim/run.py'],cwd=ROOT,env=env)
    if rc: raise SystemExit(rc)
