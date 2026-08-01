use crate::items::{Action, BuildMethod, Item};
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, Sender};
use std::time::{SystemTime, UNIX_EPOCH};

pub enum Progress {
    /// One log line to append to the scrolling output.
    Log(String),
    /// A step finished (successfully or not) -- advances the progress bar.
    StepDone,
    /// A step finished with an error (sent alongside a Log line with the
    /// details -- kept separate so the UI can count failures without
    /// string-matching log text).
    StepFailed,
    /// A step was skipped because the user answered "no" to an overwrite
    /// prompt -- distinct from StepFailed (nothing went wrong) but still
    /// advances the progress bar like StepDone.
    StepSkipped,
    /// User cancelled: stopped before finishing every requested item.
    Cancelled,
    /// Every requested item ran (or cancellation was seen) and the worker
    /// thread is about to exit.
    Finished,
    /// A dotfiles target already exists with *different* content than the
    /// repo's copy -- blocks the worker thread until an Answer arrives on
    /// the paired channel (see `run`'s `answers` parameter).
    ConfirmOverwrite(String),
}

#[derive(Clone, Copy)]
pub enum Answer {
    Yes,
    No,
    /// Yes to this one and every future prompt this run -- no more asking.
    AllYes,
}

/// Tracks whether overwrite prompts still need asking, and asks over `tx` /
/// blocks on `answers` when they do. GTK theme installs deliberately don't
/// go through this -- ~/.themes holds build *output*, not personal config,
/// so it's always safe to just replace like it already did before prompting
/// existed.
struct Prompter<'a> {
    tx: &'a Sender<Progress>,
    answers: &'a Receiver<Answer>,
    auto_yes: bool,
}

impl Prompter<'_> {
    fn confirm_overwrite(&mut self, target: &Path) -> bool {
        if self.auto_yes {
            return true;
        }
        let _ = self.tx.send(Progress::ConfirmOverwrite(target.display().to_string()));
        match self.answers.recv() {
            Ok(Answer::Yes) => true,
            Ok(Answer::AllYes) => {
                self.auto_yes = true;
                true
            }
            Ok(Answer::No) => false,
            // UI side hung up (window closed, thread panicked) -- refusing
            // to touch the file is the safe default, not clobbering it.
            Err(_) => false,
        }
    }
}

/// Runs every checked item in order, reporting each step over `tx`. Meant to
/// run on a background thread so the UI stays responsive and redraws while
/// this works. Cancellation is checked before each item (not mid-item -- a
/// `git clone` or `install.sh` already running isn't interrupted, only the
/// next one is skipped) so it can't leave a single step half-applied.
pub fn run(items: &[Item], home: &Path, tx: &Sender<Progress>, cancel: &AtomicBool, answers: &Receiver<Answer>) {
    let backup_dir = home.join(format!(
        ".config-backup-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    ));
    let mut prompter = Prompter { tx, answers, auto_yes: false };

    for item in items.iter().filter(|i| i.checked) {
        if cancel.load(Ordering::Relaxed) {
            let _ = tx.send(Progress::Log(format!(
                "Cancelled -- {} remaining item(s) skipped.",
                items.iter().filter(|i| i.checked).count()
            )));
            let _ = tx.send(Progress::Cancelled);
            return;
        }

        let _ = tx.send(Progress::Log(format!("── {} ──", item.label)));
        let result = match &item.action {
            Action::ConfigDir { name, source } => {
                copy_one(source, &home.join(".config").join(name), &backup_dir, &mut prompter)
            }
            Action::ConfigFile { name, source } => {
                copy_one(source, &home.join(".config").join(name), &backup_dir, &mut prompter)
            }
            Action::HomeFile { name, source } => install_home_file(name, source, home, &backup_dir, &mut prompter),
            Action::Applications { source } => install_applications(source, home, &backup_dir, &mut prompter),
            Action::GtkTheme(theme) => install_gtk_theme(theme, home, tx).map(|()| Applied::Done),
            Action::PacmanPackages | Action::AurPackages => {
                unreachable!("main.rs extracts package items via App::take_checked_packages before start_install ever sees them -- see run_packages")
            }
        };
        match result {
            Err(e) => {
                let _ = tx.send(Progress::Log(format!("  ERROR: {e}")));
                let _ = tx.send(Progress::StepFailed);
            }
            Ok(Applied::Skipped) => {
                let _ = tx.send(Progress::Log("  skipped (answered no)".to_string()));
                let _ = tx.send(Progress::StepSkipped);
            }
            Ok(Applied::Done) => {}
        }
        let _ = tx.send(Progress::StepDone);
    }

    let _ = tx.send(Progress::Log(String::new()));
    let _ = tx.send(Progress::Log(
        "Log in again (or i3-msg restart) so i3/polybar/dunst pick up the new config."
            .to_string(),
    ));
    let _ = tx.send(Progress::Finished);
}

/// Whether a copy actually happened or the user declined it. Not an error
/// either way -- `run` reports Skipped as its own StepSkipped, separate from
/// StepFailed.
enum Applied {
    Done,
    Skipped,
}

/// gitconfig is a seed, not a synced file: once it exists it's expected to
/// carry machine-local user.name/user.email that aren't in the repo, so this
/// must never overwrite it (matches install.sh's behavior) -- doesn't even
/// go through the confirm prompt, since the answer is always "no" here.
fn install_home_file(
    name: &str,
    source: &Path,
    home: &Path,
    backup_dir: &Path,
    prompter: &mut Prompter,
) -> io::Result<Applied> {
    let target = home.join(format!(".{name}"));
    if name == "gitconfig" && target.exists() {
        let _ = prompter.tx.send(Progress::Log(
            "  .gitconfig already present, leaving local identity untouched".to_string(),
        ));
        return Ok(Applied::Done);
    }
    copy_one(source, &target, backup_dir, prompter)
}

fn install_applications(
    source_dir: &Path,
    home: &Path,
    backup_dir: &Path,
    prompter: &mut Prompter,
) -> io::Result<Applied> {
    let target_dir = home.join(".local/share/applications");
    std::fs::create_dir_all(&target_dir)?;
    // One "no" among several launcher files shouldn't lose the rest --
    // apply what was approved, remember whether anything was actually
    // skipped, and report that once at the end.
    let mut any_skipped = false;
    for entry in std::fs::read_dir(source_dir)? {
        let entry = entry?;
        let name = entry.file_name();
        if matches!(copy_one(&entry.path(), &target_dir.join(&name), backup_dir, prompter)?, Applied::Skipped) {
            any_skipped = true;
        }
    }
    Ok(if any_skipped { Applied::Skipped } else { Applied::Done })
}

/// Copies a single file or a whole directory tree, skipping the copy
/// entirely if the target already has identical content (mirrors
/// install.sh's `diff -rq` short-circuit so re-running this is cheap and
/// doesn't spam backups/prompts for unchanged files). If it differs, asks
/// before backing up and overwriting.
fn copy_one(source: &Path, target: &Path, backup_dir: &Path, prompter: &mut Prompter) -> io::Result<Applied> {
    if target.exists() && !is_symlink(target) && trees_equal(source, target)? {
        let _ = prompter.tx.send(Progress::Log(format!(
            "  {} already up to date, skipping",
            target.display()
        )));
        return Ok(Applied::Done);
    }

    if (target.exists() || is_symlink(target)) && !prompter.confirm_overwrite(target) {
        return Ok(Applied::Skipped);
    }

    if target.exists() || is_symlink(target) {
        std::fs::create_dir_all(backup_dir)?;
        let dest = backup_dir.join(target.file_name().unwrap());
        let _ = prompter.tx.send(Progress::Log(format!(
            "  backing up existing {} -> {}",
            target.display(),
            dest.display()
        )));
        std::fs::rename(target, &dest)?;
    }

    if let Some(parent) = target.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let _ = prompter.tx.send(Progress::Log(format!("  copying to {}", target.display())));
    if source.is_dir() {
        copy_dir_recursive(source, target)?;
        mark_scripts_executable(target)?;
    } else {
        std::fs::copy(source, target)?;
    }
    Ok(Applied::Done)
}

fn is_symlink(path: &Path) -> bool {
    std::fs::symlink_metadata(path).map(|m| m.file_type().is_symlink()).unwrap_or(false)
}

fn copy_dir_recursive(source: &Path, target: &Path) -> io::Result<()> {
    std::fs::create_dir_all(target)?;
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        let from = entry.path();
        let to = target.join(entry.file_name());
        let file_type = entry.file_type()?;
        if file_type.is_symlink() {
            // Recreate the symlink itself rather than dereferencing it
            // (matches `cp -r`'s default, which install.sh relied on) --
            // GTK icon themes lean on internal symlinks heavily to
            // deduplicate near-identical assets, and some can be
            // intentionally relative/dangling until sibling files are in
            // place, so resolving through them here would be both wrong
            // and liable to fail outright.
            let link_target = std::fs::read_link(&from)?;
            std::os::unix::fs::symlink(&link_target, &to)?;
        } else if file_type.is_dir() {
            copy_dir_recursive(&from, &to)?;
        } else {
            std::fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

fn mark_scripts_executable(dir: &Path) -> io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    if dir.is_dir() {
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                mark_scripts_executable(&path)?;
            } else if path.extension().is_some_and(|e| e == "sh") {
                let mut perms = std::fs::metadata(&path)?.permissions();
                perms.set_mode(perms.mode() | 0o111);
                std::fs::set_permissions(&path, perms)?;
            }
        }
    }
    Ok(())
}

/// Recursive structural + content comparison, standing in for `diff -rq`.
fn trees_equal(a: &Path, b: &Path) -> io::Result<bool> {
    let a_is_dir = a.is_dir();
    if a_is_dir != b.is_dir() {
        return Ok(false);
    }
    if !a_is_dir {
        return Ok(std::fs::read(a)? == std::fs::read(b)?);
    }
    let mut a_names: Vec<_> = std::fs::read_dir(a)?.filter_map(|e| e.ok()).map(|e| e.file_name()).collect();
    let mut b_names: Vec<_> = std::fs::read_dir(b)?.filter_map(|e| e.ok()).map(|e| e.file_name()).collect();
    a_names.sort();
    b_names.sort();
    if a_names != b_names {
        return Ok(false);
    }
    for name in a_names {
        if !trees_equal(&a.join(&name), &b.join(&name))? {
            return Ok(false);
        }
    }
    Ok(true)
}

fn install_gtk_theme(theme: &crate::items::GtkTheme, home: &Path, tx: &Sender<Progress>) -> io::Result<()> {
    let clone_dir = home.join(".cache/dotfiles-installer").join(theme.name);
    if clone_dir.exists() {
        std::fs::remove_dir_all(&clone_dir)?;
    }
    std::fs::create_dir_all(clone_dir.parent().unwrap())?;

    let _ = tx.send(Progress::Log(format!("  cloning {}", theme.repo_url)));
    // Captured, not inherited: `git clone`'s live \r progress meter assumes
    // it owns the terminal, which corrupts ratatui's alternate-screen
    // rendering if it's allowed to write straight through.
    let output = Command::new("git")
        .args(["clone", "--depth", "1", "--quiet", theme.repo_url, clone_dir.to_str().unwrap()])
        .output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(io::Error::other(format!(
            "git clone failed for {}: {}",
            theme.repo_url,
            stderr.lines().next_back().unwrap_or("(no output)")
        )));
    }

    let themes_dir = home.join(".themes");
    std::fs::create_dir_all(&themes_dir)?;

    match &theme.build {
        BuildMethod::PlainCopy => {
            let dest = themes_dir.join(theme.name);
            if dest.exists() {
                std::fs::remove_dir_all(&dest)?;
            }
            copy_dir_recursive(&clone_dir, &dest)?;
            let _ = tx.send(Progress::Log(format!("  installed to {}", dest.display())));
        }
        BuildMethod::ViceliuceInstaller(runs) => {
            let install_script = clone_dir.join("themes/install.sh");
            let themes_dir_str = themes_dir.to_str().expect("~/.themes path must be valid UTF-8");
            for (env, args) in runs {
                let _ = tx.send(Progress::Log(format!("  install.sh {}", args.join(" "))));
                let mut cmd = Command::new("bash");
                cmd.arg(&install_script)
                    // Explicit -d instead of relying on install.sh's own
                    // $HOME/.themes default: that default is resolved from
                    // the child process's inherited HOME, which is only
                    // ever right by coincidence when `home` here happens to
                    // match the real environment (e.g. it silently wrote
                    // into the real ~/.themes during testing against a
                    // scratch home before this was added).
                    .args(["-d", themes_dir_str])
                    .args(args)
                    .env("HOME", home)
                    .current_dir(&clone_dir);
                for (k, v) in env {
                    cmd.env(k, v);
                }
                let output = cmd.output()?;
                if !output.status.success() {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    return Err(io::Error::other(format!(
                        "install.sh {} failed: {}",
                        args.join(" "),
                        stderr.lines().next_back().unwrap_or("(no output)")
                    )));
                }
            }
        }
    }

    Ok(())
}

/// CARGO_MANIFEST_DIR is baked in at compile time as installer/'s absolute
/// path, so this is right regardless of what directory the binary is
/// actually invoked from.
pub fn default_repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("installer/ always has a parent directory")
        .to_path_buf()
}

/// Runs on the main thread with the terminal handed back to it (main.rs
/// leaves the alternate screen and disables raw mode before calling this,
/// then restores both after) -- sudo/pacman/paru/makepkg all need a real
/// tty for password prompts and their own interactive [Y/n] confirmations,
/// which conflicts with ratatui owning the terminal, so this can't go
/// through the normal worker-thread `run` path above. Fully synchronous;
/// prints straight to the inherited terminal instead of going through
/// `Progress`, since there's no ratatui log view to send it to right now.
pub fn run_packages(items: &[Item]) {
    for item in items {
        match &item.action {
            Action::PacmanPackages => {
                println!("\n==> sudo pacman -S --needed {}\n", crate::items::PACMAN_PACKAGES.join(" "));
                let status =
                    Command::new("sudo").args(["pacman", "-S", "--needed"]).args(crate::items::PACMAN_PACKAGES).status();
                report_status("pacman", status);
            }
            Action::AurPackages => {
                let has_paru = Command::new("paru").arg("--version").output().map(|o| o.status.success()).unwrap_or(false);
                if !has_paru {
                    println!("\n==> paru not found, bootstrapping it first (needs sudo + base-devel/git)\n");
                    let status = Command::new("sudo").args(["pacman", "-S", "--needed", "base-devel", "git"]).status();
                    if !report_status("pacman (base-devel/git)", status) {
                        continue;
                    }
                    let build_dir = std::env::temp_dir().join("dotfiles-installer-paru-build");
                    let _ = std::fs::remove_dir_all(&build_dir);
                    let status = Command::new("git")
                        .args(["clone", "https://aur.archlinux.org/paru.git", build_dir.to_str().unwrap()])
                        .status();
                    if !report_status("git clone paru", status) {
                        continue;
                    }
                    let status = Command::new("makepkg").arg("-si").current_dir(&build_dir).status();
                    if !report_status("makepkg -si (paru)", status) {
                        continue;
                    }
                }
                println!("\n==> paru -S {}\n", crate::items::AUR_PACKAGES.join(" "));
                let status = Command::new("paru").arg("-S").args(crate::items::AUR_PACKAGES).status();
                report_status("paru", status);
            }
            _ => {}
        }
    }
    println!("\nPress Enter to continue to the dotfiles install...");
    let mut discard = String::new();
    let _ = io::stdin().read_line(&mut discard);
}

fn report_status(what: &str, status: io::Result<std::process::ExitStatus>) -> bool {
    match status {
        Ok(s) if s.success() => true,
        Ok(s) => {
            println!("!! {what} exited with {s}");
            false
        }
        Err(e) => {
            println!("!! failed to run {what}: {e}");
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::items::{Category, GtkTheme};
    use std::sync::mpsc;
    use std::thread;

    /// Exercises the real copy logic (dir copy, loose-file copy, gitconfig
    /// seed-not-sync special case, backup-on-conflict, skip-if-unchanged)
    /// plus one real GTK theme download+build against a fake $HOME, so
    /// nothing here can touch the actual live ~/.config. Ignored by default
    /// since it hits the network (git clone) -- run explicitly with
    /// `cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn full_run_against_fake_home() {
        let tmp = std::env::temp_dir().join(format!(
            "dotfiles-installer-test-{}",
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
        ));
        let fake_repo = tmp.join("repo");
        let fake_home = tmp.join("home");
        std::fs::create_dir_all(fake_repo.join("config/i3")).unwrap();
        std::fs::create_dir_all(fake_repo.join("config/applications")).unwrap();
        std::fs::create_dir_all(fake_repo.join("home")).unwrap();
        std::fs::create_dir_all(&fake_home).unwrap();

        std::fs::write(fake_repo.join("config/i3/config"), "i3 config contents").unwrap();
        std::fs::write(fake_repo.join("config/mimeapps.list"), "loose file contents").unwrap();
        std::fs::write(fake_repo.join("config/applications/foo.desktop"), "desktop entry").unwrap();
        std::fs::write(fake_repo.join("home/xinitrc"), "xinitrc contents").unwrap();
        std::fs::write(fake_repo.join("home/gitconfig"), "repo gitconfig").unwrap();

        // Pre-existing gitconfig with a "local identity" -- must survive
        // untouched, unlike everything else.
        std::fs::write(fake_home.join(".gitconfig"), "user's real gitconfig").unwrap();

        let items = vec![
            Item {
                label: "config/i3".into(),
                description: String::new(),
                category: Category::Config,
                checked: true,
                action: Action::ConfigDir { name: "i3".into(), source: fake_repo.join("config/i3") },
            },
            Item {
                label: "config/mimeapps.list".into(),
                description: String::new(),
                category: Category::Config,
                checked: true,
                action: Action::ConfigFile {
                    name: "mimeapps.list".into(),
                    source: fake_repo.join("config/mimeapps.list"),
                },
            },
            Item {
                label: "home/xinitrc".into(),
                description: String::new(),
                category: Category::Home,
                checked: true,
                action: Action::HomeFile { name: "xinitrc".into(), source: fake_repo.join("home/xinitrc") },
            },
            Item {
                label: "home/gitconfig".into(),
                description: String::new(),
                category: Category::Home,
                checked: true,
                action: Action::HomeFile { name: "gitconfig".into(), source: fake_repo.join("home/gitconfig") },
            },
            Item {
                label: "applications".into(),
                description: String::new(),
                category: Category::Launchers,
                checked: true,
                action: Action::Applications { source: fake_repo.join("config/applications") },
            },
            Item {
                label: "Nordic".into(),
                description: String::new(),
                category: Category::GtkThemes,
                checked: true,
                action: Action::GtkTheme(GtkTheme {
                    name: "Nordic",
                    repo_url: "https://github.com/EliverLara/Nordic.git",
                    build: BuildMethod::PlainCopy,
                }),
            },
            // Exercises the other build path (Vinceliuce-family
            // themes.install.sh with BATCH_MODE unset), not just the plain
            // copy above.
            Item {
                label: "Gruvbox".into(),
                description: String::new(),
                category: Category::GtkThemes,
                checked: true,
                action: Action::GtkTheme(crate::items::gtk_themes().remove(1)),
            },
        ];

        let (tx, rx) = mpsc::channel();
        let (_answer_tx, answer_rx) = mpsc::channel();
        run(&items, &fake_home, &tx, &AtomicBool::new(false), &answer_rx);
        let logs: Vec<String> = rx.try_iter().filter_map(|p| match p {
            Progress::Log(l) => Some(l),
            _ => None,
        }).collect();

        assert_eq!(std::fs::read_to_string(fake_home.join(".config/i3/config")).unwrap(), "i3 config contents");
        assert_eq!(
            std::fs::read_to_string(fake_home.join(".config/mimeapps.list")).unwrap(),
            "loose file contents"
        );
        assert_eq!(std::fs::read_to_string(fake_home.join(".xinitrc")).unwrap(), "xinitrc contents");
        assert_eq!(
            std::fs::read_to_string(fake_home.join(".gitconfig")).unwrap(),
            "user's real gitconfig",
            "gitconfig must never be overwritten once present"
        );
        assert_eq!(
            std::fs::read_to_string(fake_home.join(".local/share/applications/foo.desktop")).unwrap(),
            "desktop entry"
        );
        assert!(
            fake_home.join(".themes/Nordic/index.theme").is_file(),
            "Nordic GTK theme should have been cloned from GitHub and copied into ~/.themes"
        );
        assert!(
            fake_home.join(".themes/Gruvbox-Dark/gtk-3.0/gtk.css").is_file(),
            "Gruvbox should have been built via its own install.sh into ~/.themes, logs: {logs:#?}"
        );
        assert!(
            fake_home.join(".themes/Gruvbox-Purple-Light/gtk-3.0/gtk.css").is_file(),
            "install.sh -t all -c dark -c light should have produced every accent/mode combo"
        );
        assert!(
            logs.iter().any(|l| l.contains("gitconfig already present")),
            "expected a log line about gitconfig being left alone, got: {logs:#?}"
        );

        // Re-running must skip the unchanged i3 config instead of backing
        // it up again.
        let (tx2, rx2) = mpsc::channel();
        let (_answer_tx2, answer_rx2) = mpsc::channel();
        run(&items[..1], &fake_home, &tx2, &AtomicBool::new(false), &answer_rx2);
        let logs2: Vec<String> = rx2.try_iter().filter_map(|p| match p {
            Progress::Log(l) => Some(l),
            _ => None,
        }).collect();
        assert!(
            logs2.iter().any(|l| l.contains("already up to date")),
            "expected an unchanged re-run to skip instead of re-copying, got: {logs2:#?}"
        );
        assert!(
            std::fs::read_dir(&fake_home).unwrap().filter_map(|e| e.ok()).all(|e| !e
                .file_name()
                .to_string_lossy()
                .starts_with(".config-backup-")),
            "an unchanged re-run should not have created a backup"
        );

        std::fs::remove_dir_all(&tmp).ok();
    }

    /// No network involved (loose file copies only) so this runs on every
    /// `cargo test`, unlike the GTK theme test above.
    #[test]
    fn cancel_stops_before_the_next_item_and_reports_what_was_skipped() {
        let tmp = std::env::temp_dir().join(format!(
            "dotfiles-installer-canceltest-{}",
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
        ));
        let fake_repo = tmp.join("repo");
        let fake_home = tmp.join("home");
        std::fs::create_dir_all(&fake_repo).unwrap();
        std::fs::create_dir_all(&fake_home).unwrap();
        std::fs::write(fake_repo.join("a.conf"), "a").unwrap();
        std::fs::write(fake_repo.join("b.conf"), "b").unwrap();

        let items = vec![
            Item {
                label: "a.conf".into(),
                description: String::new(),
                category: Category::Config,
                checked: true,
                action: Action::ConfigFile { name: "a.conf".into(), source: fake_repo.join("a.conf") },
            },
            Item {
                label: "b.conf".into(),
                description: String::new(),
                category: Category::Config,
                checked: true,
                action: Action::ConfigFile { name: "b.conf".into(), source: fake_repo.join("b.conf") },
            },
        ];

        // Already cancelled before run() even starts -- simulates the user
        // hitting the cancel key while the first item is still in flight,
        // by the time the *next* iteration checks the flag.
        let cancel = AtomicBool::new(true);
        let (tx, rx) = mpsc::channel();
        let (_answer_tx, answer_rx) = mpsc::channel();
        run(&items, &fake_home, &tx, &cancel, &answer_rx);
        let messages: Vec<Progress> = rx.try_iter().collect();

        assert!(
            !fake_home.join(".config/a.conf").exists(),
            "cancelled before the first item ran, nothing should have been copied"
        );
        assert!(
            messages.iter().any(|m| matches!(m, Progress::Cancelled)),
            "expected a Cancelled message"
        );
        assert!(
            !messages.iter().any(|m| matches!(m, Progress::Finished)),
            "Cancelled and Finished are mutually exclusive -- got both"
        );

        std::fs::remove_dir_all(&tmp).ok();
    }

    /// Drives `run` the way the real UI thread does: read Progress off
    /// `rx`, answer any ConfirmOverwrite prompts, until Finished/Cancelled.
    /// No network involved, runs on every `cargo test`.
    #[test]
    fn overwrite_prompt_no_skips_yes_applies_and_backs_up() {
        let tmp = std::env::temp_dir().join(format!(
            "dotfiles-installer-prompttest-{}",
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
        ));
        let fake_repo = tmp.join("repo");
        let fake_home = tmp.join("home");
        std::fs::create_dir_all(fake_repo.join(".config")).unwrap();
        std::fs::create_dir_all(fake_home.join(".config")).unwrap();
        std::fs::write(fake_repo.join(".config/a.conf"), "A-NEW").unwrap();
        std::fs::write(fake_repo.join(".config/b.conf"), "B-NEW").unwrap();
        // Pre-existing, *different* content -- these are what should
        // trigger a prompt instead of a silent overwrite.
        std::fs::write(fake_home.join(".config/a.conf"), "A-OLD").unwrap();
        std::fs::write(fake_home.join(".config/b.conf"), "B-OLD").unwrap();

        let items = vec![
            Item {
                label: "a.conf".into(),
                description: String::new(),
                category: Category::Config,
                checked: true,
                action: Action::ConfigFile { name: "a.conf".into(), source: fake_repo.join(".config/a.conf") },
            },
            Item {
                label: "b.conf".into(),
                description: String::new(),
                category: Category::Config,
                checked: true,
                action: Action::ConfigFile { name: "b.conf".into(), source: fake_repo.join(".config/b.conf") },
            },
        ];

        let (tx, rx) = mpsc::channel();
        let (answer_tx, answer_rx) = mpsc::channel();
        let home = fake_home.clone();
        let cancel = AtomicBool::new(false);
        let handle = thread::spawn(move || run(&items, &home, &tx, &cancel, &answer_rx));

        let mut prompted_for = Vec::new();
        loop {
            match rx.recv().expect("worker dropped tx without sending Finished") {
                Progress::ConfirmOverwrite(what) => {
                    let answer = if what.ends_with("a.conf") { Answer::No } else { Answer::Yes };
                    prompted_for.push(what);
                    answer_tx.send(answer).unwrap();
                }
                Progress::Finished => break,
                _ => {}
            }
        }
        handle.join().unwrap();

        assert_eq!(prompted_for.len(), 2, "both differing files should have prompted");
        assert_eq!(
            std::fs::read_to_string(fake_home.join(".config/a.conf")).unwrap(),
            "A-OLD",
            "answered No -- must not have been touched"
        );
        assert_eq!(
            std::fs::read_to_string(fake_home.join(".config/b.conf")).unwrap(),
            "B-NEW",
            "answered Yes -- should have been overwritten with the repo's version"
        );

        let backup_dir = std::fs::read_dir(&fake_home)
            .unwrap()
            .filter_map(|e| e.ok())
            .find(|e| e.file_name().to_string_lossy().starts_with(".config-backup-"))
            .expect("b.conf's old content should have been backed up before overwriting");
        assert_eq!(std::fs::read_to_string(backup_dir.path().join("b.conf")).unwrap(), "B-OLD");
        assert!(
            !backup_dir.path().join("a.conf").exists(),
            "a.conf was skipped (No), so nothing about it should be in the backup either"
        );

        std::fs::remove_dir_all(&tmp).ok();
    }
}
