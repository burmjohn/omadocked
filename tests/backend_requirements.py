"""Explicit backend inventory from phase3-harness-safety-review/report.md.

non-qt is NOT subprocess-free. Mixed helper modules are conservatively in the
offscreen group. Manual/action runners are outside the automated full gate.
"""
from spawn_safety import UnsafeLaunch

MODULES = {
    **dict.fromkeys('test_daily_adapter test_desktop_action_adapter test_window_adapter test_tooltip_adapter test_host_overlay'.split(), 'native'),
    **dict.fromkeys('test_attention_native test_host_visibility test_preview_native test_advanced_tooltip_native test_advanced_tooltip_preference test_appearance_preferences test_delay_preferences test_folder_lifetime test_folder_service test_folder_transactions test_follow_output_native test_launch_feedback test_launch_preference test_overlap_native test_overlap_socket test_overlap_utf8 test_phase3_controls test_shell_gestures test_window_restore_integration test_app_service test_attention_sound test_parking_service test_astra_regressions test_remediation_contracts test_storage_lifecycle'.split(), 'offscreen'),
    **dict.fromkeys('test_app_launcher test_config_store test_desktop_action_harness test_eligible_fifo test_folder_actions test_folder_scan test_harness test_measurement test_monitor_harness test_omadock_import test_parking_helper test_recovery_cli test_recovery_harness test_spawn_safety'.split(), 'non-qt'),
}
NATIVE_METHODS = {
    'test_attention_native': {'test_root_lock_and_standalone_capabilities'},
    'test_preview_native': {'test_native_null_source_loader_disposal', 'test_production_resolver_rejects_stale_regrouped_removed_and_parked'},
}
EXCLUDED_METHODS = {'test_readonly_live_source_no_actions'}


def backend_for(test_id):
    module, _, method = test_id.split('.')[-3:]
    if module not in MODULES:
        raise UnsafeLaunch(f'unclassified test: {test_id}')
    if method in EXCLUDED_METHODS:
        raise UnsafeLaunch('live-read test requires separate consent; not part of automated backend gates')
    if method in NATIVE_METHODS.get(module, ()):
        return 'native'
    return MODULES[module]
