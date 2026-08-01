use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;

use crate::installer::{self, Answer, Progress};
use crate::items::{self, Category, Item};

pub enum Screen {
    Checklist,
    Progress,
    Done,
}

pub struct App {
    pub items: Vec<Item>,
    /// Index into `Category::ALL` -- which tab is active.
    pub current_tab: usize,
    /// Index into `self.items`, always one that's visible in the current
    /// tab + search filter.
    pub selected: usize,
    pub search_active: bool,
    pub search_query: String,
    pub screen: Screen,
    pub log: Vec<String>,
    pub total_steps: usize,
    pub done_steps: usize,
    pub error_count: usize,
    pub skipped_count: usize,
    pub cancelled: bool,
    /// Set while the worker thread is blocked waiting for an overwrite
    /// decision -- Some(description of what would be overwritten).
    pub pending_confirm: Option<String>,
    pub home: PathBuf,
    rx: Option<Receiver<Progress>>,
    answer_tx: Option<Sender<Answer>>,
    cancel: Arc<AtomicBool>,
    pub should_quit: bool,
}

impl App {
    pub fn new(repo_root: PathBuf, home: PathBuf) -> Self {
        let items = items::collect(&repo_root);
        let mut app = Self {
            items,
            current_tab: 0,
            selected: 0,
            search_active: false,
            search_query: String::new(),
            screen: Screen::Checklist,
            log: Vec::new(),
            total_steps: 0,
            done_steps: 0,
            error_count: 0,
            skipped_count: 0,
            cancelled: false,
            pending_confirm: None,
            home,
            rx: None,
            answer_tx: None,
            cancel: Arc::new(AtomicBool::new(false)),
            should_quit: false,
        };
        app.selected = app.visible_items().first().copied().unwrap_or(0);
        app
    }

    pub fn current_tab_category(&self) -> Category {
        Category::ALL[self.current_tab]
    }

    /// Indices into `self.items` visible right now: on the active tab, and
    /// (if a search is active) whose label matches it.
    pub fn visible_items(&self) -> Vec<usize> {
        let tab = self.current_tab_category();
        let query = self.search_query.to_lowercase();
        (0..self.items.len())
            .filter(|&i| self.items[i].category == tab)
            .filter(|&i| query.is_empty() || self.items[i].label.to_lowercase().contains(&query))
            .collect()
    }

    pub fn move_selection(&mut self, delta: i32) {
        let visible = self.visible_items();
        if visible.is_empty() {
            return;
        }
        let pos = visible.iter().position(|&i| i == self.selected).unwrap_or(0) as i32;
        let len = visible.len() as i32;
        let next = (pos + delta).rem_euclid(len);
        self.selected = visible[next as usize];
    }

    pub fn next_tab(&mut self) {
        self.current_tab = (self.current_tab + 1) % Category::ALL.len();
        self.reselect_after_filter_change();
    }

    pub fn prev_tab(&mut self) {
        self.current_tab = (self.current_tab + Category::ALL.len() - 1) % Category::ALL.len();
        self.reselect_after_filter_change();
    }

    /// Called whenever the tab or search query changes: the previously
    /// selected item may no longer be visible, so snap to the first visible
    /// one instead.
    fn reselect_after_filter_change(&mut self) {
        let visible = self.visible_items();
        if !visible.contains(&self.selected) {
            self.selected = visible.first().copied().unwrap_or(self.selected);
        }
    }

    pub fn enter_search(&mut self) {
        self.search_active = true;
    }

    /// Esc: leave search entry AND clear the filter, showing everything on
    /// this tab again -- distinct from Enter, which keeps the filter
    /// applied so a narrowed-down view can still be browsed with j/k.
    pub fn cancel_search(&mut self) {
        self.search_active = false;
        self.search_query.clear();
        self.reselect_after_filter_change();
    }

    pub fn confirm_search(&mut self) {
        self.search_active = false;
    }

    pub fn search_push(&mut self, c: char) {
        self.search_query.push(c);
        self.reselect_after_filter_change();
    }

    pub fn search_backspace(&mut self) {
        self.search_query.pop();
        self.reselect_after_filter_change();
    }

    pub fn toggle_selected(&mut self) {
        if let Some(item) = self.items.get_mut(self.selected) {
            item.checked = !item.checked;
        }
    }

    /// Toggles every currently visible item together (all-on if any are
    /// off, all-off if all are already on) -- scoped to the active tab, and
    /// further to the search filter if one's applied, so narrowing "GTK
    /// Themes" down to "gruvbox" and pressing `a` only touches that one.
    pub fn toggle_all(&mut self) {
        let visible = self.visible_items();
        let all_checked = visible.iter().all(|&i| self.items[i].checked);
        for i in visible {
            self.items[i].checked = !all_checked;
        }
    }

    /// Pulls out just the checked package-install items, leaving everything
    /// else in place for `start_install`. Called first, from main.rs, since
    /// those need the real terminal handed back to them for sudo/pacman/
    /// paru prompts -- see `installer::run_packages`.
    pub fn take_checked_packages(&mut self) -> Vec<Item> {
        let all = std::mem::take(&mut self.items);
        let (packages, rest): (Vec<Item>, Vec<Item>) =
            all.into_iter().partition(|item| item.checked && matches!(item.category, Category::Packages));
        self.items = rest;
        packages
    }

    /// Moves the checklist into the repo's actual items (they can't be
    /// cloned cheaply -- Item holds owned data with no Clone impl needed
    /// elsewhere), spawns the worker thread, and switches to the progress
    /// screen.
    pub fn start_install(&mut self) {
        let checked: Vec<Item> = std::mem::take(&mut self.items)
            .into_iter()
            .filter(|i| i.checked)
            .collect();
        self.total_steps = checked.len();
        self.done_steps = 0;
        self.error_count = 0;
        self.skipped_count = 0;
        self.screen = Screen::Progress;

        let (tx, rx) = mpsc::channel();
        let (answer_tx, answer_rx) = mpsc::channel();
        self.rx = Some(rx);
        self.answer_tx = Some(answer_tx);
        self.cancel = Arc::new(AtomicBool::new(false));
        let cancel = Arc::clone(&self.cancel);
        let home = self.home.clone();
        thread::spawn(move || {
            installer::run(&checked, &home, &tx, &cancel, &answer_rx);
        });
    }

    /// Answers a pending overwrite prompt and unblocks the worker thread.
    pub fn answer_confirm(&mut self, answer: Answer) {
        if let Some(tx) = &self.answer_tx {
            let _ = tx.send(answer);
        }
        self.pending_confirm = None;
    }

    /// Esc or Ctrl+C while installing: best-effort, cooperative cancel --
    /// stops before the *next* item starts rather than killing whatever
    /// git-clone/install.sh is running mid-step, so a step can never be
    /// left half-applied. A no-op while an overwrite prompt is pending --
    /// answer that first (main.rs routes cancel keys away from this while
    /// pending_confirm is set, this guard is the second line of defense).
    pub fn request_cancel(&mut self) {
        if matches!(self.screen, Screen::Progress) && self.pending_confirm.is_none() {
            self.cancel.store(true, Ordering::Relaxed);
        }
    }

    /// Drains whatever progress messages have arrived since the last frame.
    /// Called every event-loop tick so the log/gauge update live while the
    /// worker thread runs. Naturally stops draining at a ConfirmOverwrite --
    /// the worker is blocked waiting on `answers` by the time it sends one,
    /// so there's nothing further to receive until `answer_confirm` unblocks
    /// it.
    pub fn poll_progress(&mut self) {
        let Some(rx) = &self.rx else { return };
        while let Ok(msg) = rx.try_recv() {
            match msg {
                Progress::Log(line) => {
                    if !line.is_empty() || self.log.last().is_some_and(|l| !l.is_empty()) {
                        self.log.push(line);
                    }
                }
                Progress::StepDone => self.done_steps += 1,
                Progress::StepFailed => self.error_count += 1,
                Progress::StepSkipped => self.skipped_count += 1,
                Progress::ConfirmOverwrite(what) => self.pending_confirm = Some(what),
                Progress::Cancelled => {
                    self.cancelled = true;
                    self.screen = Screen::Done;
                }
                Progress::Finished => self.screen = Screen::Done,
            }
        }
    }
}
