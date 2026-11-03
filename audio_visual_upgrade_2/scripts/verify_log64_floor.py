"""Regression for the log map with retained display floor."""
from pathlib import Path
import os, sys, subprocess, json, argparse
parser=argparse.ArgumentParser()
parser.add_argument('--tag',default='log64_floor_20261102_r1')
parser.add_argument('--keys',default='mapping,floor,wav,attack_bands,spectrum_stage1,layer_fft64,split_spectrum,split_core,circular_system,circular_board')
args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/log64_floor_20261102_r1'
base=['rtl/audio/spec_bands64.v','rtl/audio/spec_attack18.v',
      'output/log64_floor_20261102_r1/spec_bands64_linear_reference.v',
      'output/log64_floor_20261102_r1/spec_bands64_log_reference.v','tb/tb_log64_floor.v']
scenarios={
 'mapping':['log_widths_and_filtered_averages','nonoverlap_64_bands','bars_done_64','bands64_second_frame_smoothing','bands64_reset_history'],
 'floor':['floor_all_256_codes_and_boundaries','mixed_bins_and_original_smoothing','history_decays_to_zero','reset_restores_silence','original_attack_outputs_cycle_identical'],
 'wav':['actual_wav_187p5_fourth_bar_stable_within_4_levels','actual_wav_outside_three_tone_bins_zero','actual_wav_original_attack_preserved']}
for key in args.keys.split(','):
    prefix=args.tag+'_'+key
    assert not (ROOT/'sim'/(prefix+'_sim_result.json')).exists(),'Preserve '+prefix
    if key in scenarios:
        files=base+(['rtl/audio/spec_window.v','rtl/audio/spec_fft.v','tb/tb_log64_floor_wav.v'] if key=='wav' else [])
        top='tb_log64_floor'+('_wav' if key=='wav' else '')
        if key=='mapping': files=['rtl/audio/spec_bands64.v','tb/tb_log64_mapping.v'];top='tb_log64_mapping'
        config={'dut_top':'work.spec_bands64','tb_top':'work.'+top,
                'libraries':[{'name':'work','sources':[{'path':p,'language':'verilog'} for p in files]}]}
        if key=='wav':config['data_files']=['output/display_floor_20261102_r1/tone_left_12bit.hex']
        config_path=OUT/(args.tag+'_modelsim_'+key+'.json');expected_path=OUT/(args.tag+'_expected_'+key+'.json')
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
    if rc:raise SystemExit(rc)
