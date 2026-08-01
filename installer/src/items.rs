use std::path::{Path, PathBuf};

/// A checklist section header. Order here is display order.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Category {
    Packages,
    Config,
    Home,
    Launchers,
    GtkThemes,
}

impl Category {
    pub fn title(self) -> &'static str {
        match self {
            Category::Packages => "System packages (pacman/AUR, needs sudo)",
            Category::Config => "Config -> ~/.config",
            Category::Home => "Home dotfiles -> ~",
            Category::Launchers => "Desktop launchers -> ~/.local/share/applications",
            Category::GtkThemes => "GTK themes (clone + build from GitHub)",
        }
    }
}

/// One selectable row in the checklist.
pub struct Item {
    pub label: String,
    pub category: Category,
    pub checked: bool,
    pub action: Action,
}

pub enum Action {
    /// `sudo pacman -S --needed <PACMAN_PACKAGES>` -- runs with the
    /// terminal handed back to it (sudo/pacman need a real tty for the
    /// password prompt and their own [Y/n] confirmations), so this and
    /// AurPackages are handled specially by main.rs before the rest of the
    /// checklist even starts, not through the normal worker-thread path.
    PacmanPackages,
    /// `paru -S <AUR_PACKAGES>`, bootstrapping paru itself first (matching
    /// the README's documented steps) if it isn't already on PATH.
    AurPackages,
    /// config/<name>/ -> ~/.config/<name>/ (whole directory, replaced atomically)
    ConfigDir { name: String, source: PathBuf },
    /// A loose file directly under config/ -> ~/.config/<name>
    ConfigFile { name: String, source: PathBuf },
    /// home/<name> -> ~/.<name> (gitconfig is special-cased in installer.rs: never
    /// overwritten once present, since it carries machine-local user.name/user.email)
    HomeFile { name: String, source: PathBuf },
    /// Every file under config/applications/ -> ~/.local/share/applications/,
    /// copied individually since that directory is shared with other apps'
    /// launcher entries.
    Applications { source: PathBuf },
    /// Clone a GTK theme's repo and build it into ~/.themes via its own
    /// install.sh (or a plain copy for Nordic, which ships pre-built).
    GtkTheme(GtkTheme),
}

pub struct GtkTheme {
    pub name: &'static str,
    pub repo_url: &'static str,
    pub build: BuildMethod,
}

/// One themes/install.sh invocation: env vars to set, then CLI args.
type InstallRun = (Vec<(&'static str, &'static str)>, Vec<&'static str>);

pub enum BuildMethod {
    /// Run themes/install.sh once per run. Every one of these themes'
    /// installers defaults to ~/.themes as -d/--dest, so no path override is
    /// needed here.
    ViceliuceInstaller(Vec<InstallRun>),
    /// Nordic ships pre-built (gtk-2.0/3.0/4.0 + index.theme at repo root),
    /// no install.sh -- just copy the clone straight into ~/.themes/Nordic.
    PlainCopy,
}

/// Kept in sync by hand with README.md's "Paket yang dibutuhkan" section --
/// update both if this list changes.
pub const PACMAN_PACKAGES: &[&str] = &[
    "i3-wm", "polybar", "rofi", "dunst", "picom", "thunar", "thunar-archive-plugin",
    "thunar-media-tags-plugin", "thunar-shares-plugin", "thunar-volman", "playerctl", "ddcutil",
    "flatpak", "xdotool", "slop", "ffmpeg", "xclip", "feh", "xorg-xrandr", "xorg-setxkbmap",
    "xorg-xset", "numlockx", "vim", "samba", "smbclient", "ufw", "networkmanager",
    "nm-connection-editor", "bluez", "bluez-utils", "kitty", "libpulse", "pavucontrol",
    "autorandr", "qt5ct", "qt6ct", "btop", "mpv", "libqalculate", "xarchiver", "htop",
    "polkit-gnome", "autotiling", "udiskie", "firefox", "brightnessctl", "ttf-jetbrains-mono-nerd",
    "otf-font-awesome", "noto-fonts", "papirus-icon-theme",
];

/// Same deal -- kept in sync by hand with README.md's AUR section.
pub const AUR_PACKAGES: &[&str] =
    &["gtkhash-thunar", "edid-decode", "betterlockscreen", "i3lock-color", "python-pywal16", "greenclip", "bibata-cursor-theme"];

/// Scans the repo's config/ and home/ directories and returns the checklist,
/// grouped into Category sections in display order.
pub fn collect(repo_root: &Path) -> Vec<Item> {
    let mut items = Vec::new();
    let config_dir = repo_root.join("config");
    let home_dir = repo_root.join("home");

    // Off by default, unlike everything else here: this is the one part of
    // the checklist that runs `sudo` and touches the system outside $HOME,
    // so re-running the installer later (the common case -- see README's
    // "aman dijalankan berkali-kali") shouldn't ambush anyone with a sudo
    // prompt and a package (re)install they didn't ask for this time.
    items.push(Item {
        label: format!("pacman -S --needed ({} paket)", PACMAN_PACKAGES.len()),
        category: Category::Packages,
        checked: false,
        action: Action::PacmanPackages,
    });
    items.push(Item {
        label: format!("paru -S ({} paket AUR, install paru dulu kalau belum ada)", AUR_PACKAGES.len()),
        category: Category::Packages,
        checked: false,
        action: Action::AurPackages,
    });

    let mut app_dirs: Vec<PathBuf> = Vec::new();
    let mut loose_files: Vec<PathBuf> = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&config_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if name == "applications" {
                continue; // handled separately below
            }
            if path.is_dir() {
                app_dirs.push(path);
            } else {
                loose_files.push(path);
            }
        }
    }
    app_dirs.sort();
    loose_files.sort();

    for source in app_dirs {
        let name = source.file_name().unwrap().to_string_lossy().into_owned();
        items.push(Item {
            label: name.clone(),
            category: Category::Config,
            checked: true,
            action: Action::ConfigDir { name, source },
        });
    }
    for source in loose_files {
        let name = source.file_name().unwrap().to_string_lossy().into_owned();
        items.push(Item {
            label: name.clone(),
            category: Category::Config,
            checked: true,
            action: Action::ConfigFile { name, source },
        });
    }

    if let Ok(entries) = std::fs::read_dir(&home_dir) {
        let mut home_files: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
        home_files.sort();
        for source in home_files {
            let name = source.file_name().unwrap().to_string_lossy().into_owned();
            items.push(Item {
                label: format!(".{name}"),
                category: Category::Home,
                checked: true,
                action: Action::HomeFile { name, source },
            });
        }
    }

    let apps_dir = config_dir.join("applications");
    if apps_dir.is_dir() {
        let count = std::fs::read_dir(&apps_dir).map(|d| d.count()).unwrap_or(0);
        items.push(Item {
            label: format!("{count} launcher entries"),
            category: Category::Launchers,
            checked: true,
            action: Action::Applications { source: apps_dir },
        });
    }

    for theme in gtk_themes() {
        let owner_repo = theme.repo_url.trim_start_matches("https://github.com/").trim_end_matches(".git");
        items.push(Item {
            label: format!("{} (via {owner_repo})", theme.name),
            category: Category::GtkThemes,
            checked: true,
            action: Action::GtkTheme(theme),
        });
    }

    items
}

/// The five theme families this repo's rofi theme-switcher expects in
/// ~/.themes, and exactly how each was built during the original manual
/// install (see config/i3/scripts/apply-theme-colors.sh for the resulting
/// folder names this must produce). BATCH_MODE=true is only needed for
/// Catppuccin's installer -- it's the one that pauses on an interactive
/// "apply now?" prompt without it.
pub fn gtk_themes() -> Vec<GtkTheme> {
    vec![
        GtkTheme {
            name: "Catppuccin",
            repo_url: "https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme.git",
            build: BuildMethod::ViceliuceInstaller(vec![
                (vec![("BATCH_MODE", "true")], vec!["-a", "all", "-m", "dark"]),
                (vec![("BATCH_MODE", "true")], vec!["-a", "all", "-m", "light"]),
                (vec![("BATCH_MODE", "true")], vec!["-a", "all", "-m", "dark", "--tweaks", "frappe"]),
                (vec![("BATCH_MODE", "true")], vec!["-a", "all", "-m", "dark", "--tweaks", "macchiato"]),
            ]),
        },
        GtkTheme {
            name: "Gruvbox",
            repo_url: "https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme.git",
            build: BuildMethod::ViceliuceInstaller(vec![
                (vec![], vec!["-t", "all", "-c", "dark", "-c", "light"]),
            ]),
        },
        GtkTheme {
            name: "Tokyonight",
            repo_url: "https://github.com/Fausto-Korpsvart/Tokyonight-GTK-Theme.git",
            build: BuildMethod::ViceliuceInstaller(vec![
                (vec![], vec!["-t", "all", "-c", "dark", "-c", "light"]),
            ]),
        },
        GtkTheme {
            name: "Everforest",
            repo_url: "https://github.com/Fausto-Korpsvart/Everforest-GTK-Theme.git",
            build: BuildMethod::ViceliuceInstaller(vec![
                (vec![], vec!["-t", "all", "-c", "dark", "-c", "light"]),
            ]),
        },
        GtkTheme {
            name: "Nordic",
            repo_url: "https://github.com/EliverLara/Nordic.git",
            build: BuildMethod::PlainCopy,
        },
    ]
}
