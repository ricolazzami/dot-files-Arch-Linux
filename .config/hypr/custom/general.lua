if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    hg.config({
        default_theme = "dark",
        default_preset = "pomme",
        self_sample = 0.4,
        layers = {
            enabled = true,
            mask_threshold = 0.01,
            mask_feather = 0.45,
            live_resample = true,
        },
        subsurfaces = {
            enabled = true,
            preset = "pomme",
        },
    })

    -- Quickshell UI components (Apple Liquid Glass)
    hg.layer("quickshell:verticalBar", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:bar", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:dock", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:sidebarLeft", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:sidebarRight", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:popup", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:notificationPopup", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:mediaControls", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:session", { preset = "pomme", mask_threshold = 0.01 })
    hg.layer("quickshell:cheatsheet", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:actionCenter", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:wNotificationCenter", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:wStartMenu", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:wOnScreenDisplay", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:wTaskView", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:osk", { preset = "pomme", mask_threshold = 0.01 })
    hg.layer("quickshell:polkit", { preset = "pomme", mask_threshold = 0.01 })
    hg.layer("quickshell:reloadPopup", { preset = "pomme", mask_threshold = 0.01 })
    hg.layer("quickshell:lyricbar", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:overview", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("quickshell:wallpaperSelector", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })

    -- Exclude wallpaper and non-glass overlays
    hg.layer("quickshell:background", { exclude = true })
    hg.layer("quickshell:screenCorners", { exclude = true })
    hg.layer("quickshell:overlay", { exclude = true })
    hg.layer("quickshell:regionSelector", { exclude = true })
    hg.layer("quickshell:lockWindowPusher", { exclude = true })

    -- Launchers and notifications
    hg.layer("fuzzel", { preset = "pomme", mask_threshold = 0.01, mask_feather = 0.45 })
    hg.layer("wlogout", { preset = "pomme", mask_threshold = 0.01 })
    hg.layer("swaync", { preset = "pomme", mask_threshold = 0.01 })
end

-- Mouse / Input settings
hl.config({
    input = {
        sensitivity = 0.3,
        accel_profile = "flat",
    }
})
