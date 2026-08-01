mod app;
mod installer;
mod items;
mod ui;

use std::io;
use std::time::Duration;

use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode};
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;

use app::{App, Screen};
use installer::Answer;

fn main() -> io::Result<()> {
    let repo_root = installer::default_repo_root();
    let home = std::env::var_os("HOME")
        .map(std::path::PathBuf::from)
        .expect("HOME must be set");

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut app = App::new(repo_root, home);
    let result = run(&mut terminal, &mut app);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}

fn run(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, app: &mut App) -> io::Result<()> {
    loop {
        terminal.draw(|frame| ui::draw(frame, app))?;

        if matches!(app.screen, Screen::Progress) {
            app.poll_progress();
        }

        if event::poll(Duration::from_millis(80))?
            && let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press {
                    continue;
                }
                match app.screen {
                    Screen::Checklist if app.search_active => match key.code {
                        KeyCode::Char(c) => app.search_push(c),
                        KeyCode::Backspace => app.search_backspace(),
                        KeyCode::Enter => app.confirm_search(),
                        KeyCode::Esc => app.cancel_search(),
                        _ => {}
                    },
                    Screen::Checklist => match key.code {
                        KeyCode::Up | KeyCode::Char('k') => app.move_selection(-1),
                        KeyCode::Down | KeyCode::Char('j') => app.move_selection(1),
                        KeyCode::Left | KeyCode::Char('h') | KeyCode::BackTab => app.prev_tab(),
                        KeyCode::Right | KeyCode::Char('l') | KeyCode::Tab => app.next_tab(),
                        KeyCode::Char(' ') => app.toggle_selected(),
                        KeyCode::Char('a') => app.toggle_all(),
                        KeyCode::Char('/') => app.enter_search(),
                        KeyCode::Enter => {
                            if app.items.iter().any(|i| i.checked) {
                                // sudo/pacman/paru/makepkg need the real
                                // terminal for password prompts and their
                                // own [Y/n] confirmations, so hand it back
                                // to them instead of running through the
                                // ratatui-owned worker-thread path everything
                                // else uses.
                                let packages = app.take_checked_packages();
                                if !packages.is_empty() {
                                    disable_raw_mode()?;
                                    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
                                    installer::run_packages(&packages);
                                    enable_raw_mode()?;
                                    execute!(terminal.backend_mut(), EnterAlternateScreen)?;
                                    terminal.clear()?;
                                }
                                app.start_install();
                            }
                        }
                        // Esc alone quits; Esc with a search still active is
                        // handled by the branch above instead (clears the
                        // filter first, matching rofi's own convention of
                        // Esc backing out one level at a time).
                        KeyCode::Char('q') | KeyCode::Esc => app.should_quit = true,
                        KeyCode::Char('c') if key.modifiers.contains(crossterm::event::KeyModifiers::CONTROL) => {
                            app.should_quit = true
                        }
                        _ => {}
                    },
                    // An existing config differs from the repo's -- answer
                    // before anything else (including cancel) resumes.
                    Screen::Progress if app.pending_confirm.is_some() => match key.code {
                        KeyCode::Char('y') | KeyCode::Char('Y') => app.answer_confirm(Answer::Yes),
                        KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Esc => app.answer_confirm(Answer::No),
                        KeyCode::Char('a') | KeyCode::Char('A') => app.answer_confirm(Answer::AllYes),
                        _ => {}
                    },
                    // Cooperative cancel: stops before the *next* item
                    // rather than killing whatever git-clone/install.sh is
                    // running right now, so a step can't be left half done.
                    Screen::Progress => match key.code {
                        KeyCode::Esc => app.request_cancel(),
                        KeyCode::Char('c') if key.modifiers.contains(crossterm::event::KeyModifiers::CONTROL) => {
                            app.request_cancel()
                        }
                        _ => {}
                    },
                    Screen::Done => app.should_quit = true,
                }
            }

        if app.should_quit {
            return Ok(());
        }
    }
}
