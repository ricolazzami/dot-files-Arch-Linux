-- Autostart services and plugins
hl.on("hyprland.start", function ()
    hl.exec_cmd("sleep 2 && " .. (HOME or (os.getenv("HOME") or "")) .. "/.local/bin/quickshell-lyricbar --background")
    hl.exec_cmd("hyprpm reload -n || true")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("sleep 1 && (" .. HOME .. "/qs-wallpaper-picker/scripts/restore_wallpaper.sh || awww img " .. HOME .. "/Pictures/Wallpapers/hill-house.png)")
end)
