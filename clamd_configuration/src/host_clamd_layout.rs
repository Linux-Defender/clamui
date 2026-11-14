pub const BASE_CLAMD_CONFIG_PATH: &str = match option_env!("LAZARET_CLAMD_CONFIG") {
    Some(configured_path) => configured_path,
    None => "/etc/clamav/clamd.conf",
};

pub const CLAMD_DAEMON_UNIT: &str = match option_env!("LAZARET_CLAMD_UNIT") {
    Some(configured_unit) => configured_unit,
    None => "clamav-daemon.service",
};

pub const CLAMONACC_UNIT: &str = match option_env!("LAZARET_CLAMONACC_UNIT") {
    Some(configured_unit) => configured_unit,
    None => "clamav-clamonacc.service",
};
