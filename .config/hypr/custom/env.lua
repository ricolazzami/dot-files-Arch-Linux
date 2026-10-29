

-- NVIDIA Dedicated GPU Wayland optimizations
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Ensure ~/.local/bin is in PATH for Hyprland child processes
local home_dir = os.getenv("HOME") or (HOME or "")
local path_old = os.getenv("PATH") or ""
if not string.find(path_old, home_dir .. "/.local/bin") then
    hl.env("PATH", home_dir .. "/.local/bin:" .. path_old)
end
