#![no_std]
pub fn add_mod_q(x: u32, y: u32) -> u32 {
    let s = x.wrapping_add(y);
    if s >= 8380417 { s - 8380417 } else { s }
}
