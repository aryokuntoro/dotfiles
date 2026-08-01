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

/// One rendered line in the checklist: either a non-selectable section
/// header or an index into `App::items`.
pub enum Row {
    Header(Category),
    Item(usize),
}

pub struct App {
    pub items: Vec<Item>,
    pub rows: Vec<Row>,
    /// Index into `rows`, always pointing at a `Row::Item` that's currently
    /// visible under `search_query`.
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
        let rows = build_rows(&items);
        let selected = rows.iter().position(|r| matches!(r, Row::Item(_))).unwrap_or(0);
        Self {
            items,
            rows,
            selected,
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
        }
    }

    /// Row indices (into `self.rows`) currently shown, given
    /// `search_query`: everything when empty, otherwise only items whose
    /// label contains it (case-insensitive) plus the header above each
    /// match -- an empty search never means "hide everything" the way an
    /// empty checked-set would, so headers with zero matches are just
    /// dropped instead of shown empty.
    pub fn visible_rows(&self) -> Vec<usize> {
        if self.search_query.is_empty() {
            return (0..self.rows.len()).collect();
        }
        let query = self.search_query.to_lowercase();
        let mut visible = Vec::new();
        let mut pending_header = None;
        for (i, row) in self.rows.iter().enumerate() {
            match row {
                Row::Header(_) => pending_header = Some(i),
                Row::Item(idx) => {
                    if self.items[*idx].label.to_lowercase().contains(&query) {
                        if let Some(h) = pending_header.take() {
                            visible.push(h);
                        }
                        visible.push(i);
                    }
                }
            }
        }
        visible
    }

    pub fn move_selection(&mut self, delta: i32) {
        let visible_items: Vec<usize> = self
            .visible_rows()
            .into_iter()
            .filter(|&i| matches!(self.rows[i], Row::Item(_)))
            .collect();
        if visible_items.is_empty() {
            return;
        }
        let current_pos = visible_items.iter().position(|&i| i == self.selected).unwrap_or(0) as i32;
        let len = visible_items.len() as i32;
        let next = (current_pos + delta).rem_euclid(len);
        self.selected = visible_items[next as usize];
    }

    /// Called whenever the search query changes: the previously selected
    /// row may no longer be visible, so snap to the first visible one.
    fn reselect_after_filter_change(&mut self) {
        let visible_items: Vec<usize> = self
            .visible_rows()
            .into_iter()
            .filter(|&i| matches!(self.rows[i], Row::Item(_)))
            .collect();
        if !visible_items.contains(&self.selected) {
            self.selected = visible_items.first().copied().unwrap_or(self.selected);
        }
    }

    pub fn enter_search(&mut self) {
        self.search_active = true;
    }

    /// Esc: leave search entry AND clear the filter, showing everything
    /// again -- distinct from Enter, which keeps the filter applied so a
    /// narrowed-down view can still be browsed with j/k.
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

    fn selected_item_index(&self) -> Option<usize> {
        match self.rows.get(self.selected) {
            Some(Row::Item(idx)) => Some(*idx),
            _ => None,
        }
    }

    pub fn toggle_selected(&mut self) {
        if let Some(idx) = self.selected_item_index()
            && let Some(item) = self.items.get_mut(idx)
        {
            item.checked = !item.checked;
        }
    }

    /// Toggles every currently visible item together (all-on if any are
    /// off, all-off if all are already on) -- global under an empty search,
    /// scoped to the filtered subset otherwise, so narrowing down to "gtk"
    /// and pressing `a` only touches the GTK theme rows.
    pub fn toggle_all(&mut self) {
        let visible_idx: Vec<usize> = self
            .visible_rows()
            .into_iter()
            .filter_map(|i| match self.rows[i] {
                Row::Item(idx) => Some(idx),
                Row::Header(_) => None,
            })
            .collect();
        let all_checked = visible_idx.iter().all(|&idx| self.items[idx].checked);
        for idx in visible_idx {
            self.items[idx].checked = !all_checked;
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

fn build_rows(items: &[Item]) -> Vec<Row> {
    let mut rows = Vec::with_capacity(items.len() + 4);
    let mut current: Option<Category> = None;
    for (idx, item) in items.iter().enumerate() {
        if current != Some(item.category) {
            rows.push(Row::Header(item.category));
            current = Some(item.category);
        }
        rows.push(Row::Item(idx));
    }
    rows
}
