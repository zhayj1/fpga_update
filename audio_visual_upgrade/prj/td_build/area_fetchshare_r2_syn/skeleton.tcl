# This is default flow script for normal condition: neither syn ip flow nor multi-seed mode.
# Noted that only script in editable zone can be changed. 

if { ![info exists alRun] } { source ./settings.cfg }
proc step_begin { step } {
  set stopFile ".stop.f"
  if {[file isfile .stop.f]} {
    puts ""
    puts " #Halting run"
    puts ""
    return -code error
  }
  set beginFile ".$step.begin.f"
  set platform "$::tcl_platform(platform)"
  set user "$::tcl_platform(user)"
  set pid [pid]
  set host ""
  if { [string equal $platform unix] } {
    if { [info exists ::env(HOSTNAME)] } {
      set host $::env(HOSTNAME)
    }
  } else {
    if { [info exists ::env(COMPUTERNAME)] } {
      set host $::env(COMPUTERNAME)
    }
  }
  set ch [open $beginFile w]
  puts $ch "<?xml version=\"1.0\"?>"
  puts $ch "<ProcessHandle Version=\"1\" Minor=\"0\">"
  puts $ch "    <Process Ownner=\"$user\" Host=\"$host\" Pid=\"$pid\">"
  puts $ch "    </Process>"
  puts $ch "</ProcessHandle>"
  close $ch
}
proc step_end { step } {
  set endFile ".$step.end.f"
  set ch [open $endFile w]
  close $ch
}
proc step_error { step } {
  set errorFile ".$step.error.f"
  set ch [open $errorFile w]
  close $ch
}
set stepList {read_design opt_rtl opt_gate opt_place opt_route bitgen}
set l [lsearch $stepList $start_step]
set r [lsearch $stepList $end_step]
proc prepare { step } {
  upvar device_name device_name
  upvar package_name package_name
  upvar speed speed
  upvar prj_name prj_name
  upvar parent parent
  upvar synWildParams synWildParams
  upvar phyWildParams phyWildParams
  upvar alRun alRun
  upvar singleRun singleRun
  upvar sp sp
  upvar ADCList ADCList
  upvar SDCList SDCList
  set command "import_device $device_name -package $package_name"; if { [info exists speed] } { append command " -speed ${speed}" }; eval $command
  if { ![info exists singleRun] } {
    if { [info exists alRun] } { 
        open_project ${prj_name}.al -single_run
        load_run_param -run ${alRun}
    } else {
    set command "open_project {${prj_name}.prj}"; if { $step != 0 } { append command " -noanalyze" }; eval $command
    }
  }
  set preSteps {non elaborate rtl gate place pr}
  set preStep [ lindex ${preSteps} $step ]
  if { $step == 3 } { import_db $parent/${prj_name}_${preStep}.db }\
  elseif { $step != 0 } { import_db ${prj_name}_${preStep}.db }
  set wildParams ""
  if { [info exists synWildParams] } { set wildParams ${synWildParams} } elseif { [info exists phyWildParams] } { set wildParams ${phyWildParams} }
  for { set i 0 } { $i < [llength $wildParams] } { incr i 3 } {
    set_param [lindex $wildParams $i] [lindex $wildParams [expr $i + 1]] [lindex $wildParams [expr $i + 2]]
  }
  if { [info exists singleRun] } report_param
  if { [info exists sp] } {
    if { [info exists ADCList] } { foreach adc $ADCList { read_adc $adc } }
    if { [info exists SDCList] } {
      clear_sdc -user
      foreach sdc $SDCList { read_sdc $sdc }
    }
  }
}
proc read_design_fun {} {
  upvar prj_name prj_name
  upvar top_model_name top_model_name
  upvar singleRun singleRun
  upvar ADCList ADCList
  upvar IpADCList IpADCList
  upvar SDCList SDCList
  upvar IpSDCList IpSDCList
  if { ![info exists singleRun] } { commit_param -step design }

### Editable zone for read_design ###
  elaborate -top $top_model_name
#####################################
  if { [info exists ADCList] } { foreach adc $ADCList { read_adc $adc } }
  if { [info exists IpADCList] } {
    set i 0
    while {$i < [llength $IpADCList]} {
      read_ip_adc -ip [lindex $IpADCList $i] -file [lindex $IpADCList [expr $i + 1] ]
      incr i 2
    }
  }
  if { [info exists SDCList] } { foreach sdc $SDCList { read_sdc $sdc } }
  if { [info exists IpSDCList] } {
    set i 0
    while {$i < [llength $IpSDCList]} {
      read_sdc -ip [lindex $IpSDCList $i] [lindex $IpSDCList [expr $i + 1] ]
      incr i 2
    }
  }
  export_db ${prj_name}_elaborate.db
}
proc opt_rtl_fun {} {
  upvar prj_name prj_name
  upvar singleRun singleRun
  if { ![info exists singleRun] } { commit_param -step rtl }


### Editable zone for opt_rtl ###
  upvar chipDebugger chipDebugger
  if { ![info exists chipDebugger] } {
     insert_debugger
  } else { insert_debugger $chipDebugger }
  optimize_rtl
  report_area -file ${prj_name}_rtl.area
#################################

  export_db ${prj_name}_rtl.db
}
proc opt_gate_fun {} {
  upvar prj_name prj_name
  upvar area_option area_option
  upvar singleRun singleRun
  if { ![info exists singleRun] } { commit_param -step gate }

### Editable zone for opt_gate ###
  optimize_gate ${area_option} ${prj_name}_gate.area
  legalize_phy_inst
  update_timing
  report_timing_status -file ${prj_name}_gate.ts
  report_timing_summary -file ${prj_name}_gate.timing
  flow_status -file flow.status
##################################

  export_db ${prj_name}_gate.db
}
proc opt_place_fun {} {
  upvar prj_name prj_name
  upvar cwcList cwcList
  upvar singleRun singleRun
  upvar chipDebugger chipDebugger
  upvar bkaADCList bkaADCList
  upvar arr_filter arr_filter
  upvar arr_pwns arr_pwns
  upvar arr_cong arr_cong
  if { ![info exists singleRun] } { commit_param -step place }
  if { ![info exists chipDebugger] } {
     insert_debugger
  } else { insert_debugger $chipDebugger }
  if { [info exists bkaADCList] } { 
     clear_inst_adc
     foreach adc $bkaADCList { read_adc $adc } 
  }

### Editable zone for opt_place ###
  # ---- P3/lean 骞跺眰锛氭姉鎷ュ鍙傛暟锛?鐢?锛屽疄娴嬮€氳繃 2026-10-07锛?---
  # 鑳屾櫙锛氬苟灞傜増鍦?8897 slices 鏃跺竷绾垮彧宸竴鏍?鈥斺€?PHY-8023 浣嶇疆 (x5y66_local5)锛?  #       娑変簨缃?u_core/u_playlist/ramread0_syn_60580 涓?u_core/u_playlist/index[7]锛?  #       甯冪嚎鍣?70+ 娆?rip-up 鍚?over cnt 鎭掍负 1锛岄殢鍚庣殑 ECO 涔熸竻涓嶆帀 鈬?RUN-8102銆?  # 宸叉帓闄わ紙鍚屼竴缃戣〃瀹炴祴锛夛細set_inflation_weight -inst u_core/u_playlist 1.5x / 5.0x
  #       鍧囨棤鏁堚€斺€斿竷灞€閫愪綅涓嶅彉锛圵L=954993锛夛紱place seed 3 鍙妸鍐茬獊鎸埌 (x37y55_e2beg3)锛?  #       鐘簨缃戜粛鏄袱鏉?ramread0_syn_*锛宱ver 浠嶇劧鍋滃湪 1銆?  # 鐢熸晥鏂规锛歍D 瀹樻柟 CongestionHigh 棰勮锛堟斁瀹借惤鐐?+ 鎶楁嫢濉烇級锛岄€愭潯 set_param銆?  # 瀹炴祴缁撴灉锛?792 slices(89.71%)銆乷ver=0銆丠old WNS +11ps銆乥itgen 閫氳繃銆?  set cong_params {
    {place target_density 0.6}
    {place target_density_pp 0.7}
    {place opt_max_density 50}
    {place enable_congestion_recovery on}
    {place non_crit_opt on}
    {place opt_timing high}
    {place post_place_opt high}
    {place enhanced_gp on}
    {place enhanced_beeline_opt 2}
    {place ofv 70}
    {place aggressive_opt 20}
    {place dram_area_factor 12}
  }
  foreach cp $cong_params {
    set st [lindex $cp 0]
    set pn [lindex $cp 1]
    set pv [lindex $cp 2]
    if { [catch { set_param $st $pn $pv } cerr] } {
      puts "\[L1M\] param $st $pn $pv FAILED: $cerr"
    } else {
      puts "\[L1M\] param $st $pn $pv ok"
    }
  }
  # 鈽呪槄 L1M-b锛?*甯冨眬绉嶅瓙蹇呴』鍥哄畾涓?2** 鉁楋紙90.7% 鍗犵敤涓?PnR 鎶栧姩澶у埌鑳芥敼鍙樺悎鏍间笌鍚?鉁擄級
  #   瀹炴祴锛堝悓涓€浠界綉琛ㄣ€佸悓涓€濂楀弬鏁帮級锛?  #     涓嶈绉嶅瓙 鈬?Hold WNS **鈭?0 ps** / H-EP 杩濅緥 6 / 8,886 鐗囷紙90.67%锛夆湕 **涓嶅悎鏍?*
  #     绉嶅瓙 = 2 鈬?Hold WNS **+3 ps**  / H-EP 杩濅緥 0 / 8,789 鐗囷紙89.68%锛夆湏 **褰掓。鐨勯偅涓€鐗?*
  #   鈬?涓嶅浐瀹氱瀛愶紝鎹㈠彴鏈哄櫒/閲嶈窇灏卞彲鑳芥嬁鍒颁笉鍚堟牸鐨勯偅涓€鐗?鉁楋紙鏈伐绋?鍒ゆ嵁蹇呴』鑳藉鐜?鐨勮鐭?鉁擄級
  set l1m_seed 2
  if { [info exists ::env(PL_SEED)] && [string length $::env(PL_SEED)] > 0 } { set l1m_seed $::env(PL_SEED) }
  if { [catch { set_param place seed $l1m_seed } serr] } {
    puts "\[L1M\] place seed FAILED: $serr"
  } else {
    puts "\[L1M\] place seed = $l1m_seed"
  }
  place
  update_timing -mode manhattan
  report_timing_summary -file ${prj_name}_place.timing
  report_area -io_info -file ${prj_name}_phy.area
  flow_status -file place_flow.status
  report_clock_utilization -file place_clock_utilization.txt
  if { [string equal $arr_filter true] } { flow_continue_check -step place -wns $arr_pwns -congestion $arr_cong }
###################################

  export_db ${prj_name}_place.db
}
proc opt_route_fun {} {
  upvar prj_name prj_name
  upvar singleRun singleRun
  upvar arr_filter arr_filter
  upvar arr_rwns arr_rwns
  upvar drHoldFix drHoldFix
  if { ![info exists singleRun] } { commit_param -step route }

### Editable zone for opt_route ###
  # ---- [L1M 鐢?probe2] 鍚屽睘 CongestionHigh 鐨?route 鍙傛暟 ----
  if { [catch { set_param route post_route_opt high } rerr] } {
    puts "\[L1M\] param route post_route_opt high FAILED: $rerr"
  } else {
    puts "\[L1M\] param route post_route_opt high ok"
  }
  if { [string equal $arr_filter on] && [string equal $drHoldFix on] } { 
    set_param route fix_hold off
    set_param flow qor_monitor off
  }
  route
  # ---- [L1M-b] 鏄惧紡琛ヤ竴娆?hold ----
  #   vendor 娴佺▼閲?`fix_hold` 鍙湪 `arr_filter=on` 鏃舵墠璺?鉁楋紝鏈伐绋?settings.cfg 鏄?  #   `set arr_filter false` 鈬?榛樿**涓嶈窇** 鉁擄紙`drHoldFix on` 鍙奖鍝嶄笂闈㈤偅涓垎鏀?鉁擄級銆?  #   鈽?瀹炴祴锛氭湰缃戣〃涓婂畠**娌℃湁鏀瑰彉浠讳綍涓滆タ**锛圦oR 閫愬瓧鐩稿悓 鉁擄級鈥斺€?鐣欑潃鏄綋 hold 淇濋櫓 鉁擄紝
  #     浣?鑳戒笉鑳借繃 hold"鏈€缁堢敱**绉嶅瓙**鍐冲畾 鉁擄紙瑙?opt_place 閲岄偅娈?鉁擄級銆?  if { [catch { fix_hold } fh_err] } {
    puts "\[L1M\] fix_hold FAILED: $fh_err"
  } else {
    puts "\[L1M\] fix_hold ok"
  }
  if { [string equal $arr_filter on] && [string equal $drHoldFix on] } {
    flow_continue_check -step route -wns $arr_rwns -name ${prj_name}
    fix_hold
    set_param route fix_hold on
    set_param flow qor_monitor on
    report_qor -step route -file route.qor
  }
  report_area -io_info -file ${prj_name}_phy.area
  update_timing -mode final
  report_timing_status -file ${prj_name}_phy.ts
  report_timing_summary -file ${prj_name}_pr.timing
  report_timing_exception -file ${prj_name}_exception.timing
  flow_status -file route_flow.status
  report_clock_utilization -file route_clock_utilization.txt
###################################

  export_db ${prj_name}_pr.db
}
proc bitgen_fun {} {
  upvar prj_name prj_name
  upvar cpcList cpcList
  upvar singleRun singleRun
  if { ![info exists singleRun] } { commit_param -step bitgen }
  if { [info exists cpcList] } {
    import_chipprobe_config $cpcList
    compile_probe
  }

### Editable zone for bitgen ###
  bitgen -bit $prj_name.bit
################################
  upvar chipDebugger chipDebugger
  if { ![info exists chipDebugger] } {
    setup_debugger
  } else { setup_debugger $chipDebugger }
  export_bitgen_param -file .bitgen_param.f 
}
foreach s [lrange $stepList $l $r] {
  step_begin $s
  set ACTIVESTEP $s
  set rc [catch {
    if { [string equal $s $start_step] } { prepare $l }
    ${s}_fun
  } RESULT]
  if { $rc } {
    step_error $s
    return -code error $RESULT
  } else {
    step_end $s
    unset ACTIVESTEP
  }
}
export_flow_status -s $start_step -e $end_step
