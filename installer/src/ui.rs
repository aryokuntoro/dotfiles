use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, Gauge, List, ListItem, ListState, Paragraph, Wrap};

use crate::app::{App, Screen};
use crate::items::Category;

// Named ANSI colors, not fixed RGB: this terminal's palette is remapped by
// whichever rofi/GTK theme is active (kitty's current-theme.conf, written by
// apply-theme-colors.sh), so e.g. Color::Black is that theme's *background*
// color, not literal black -- using it as foreground-on-colored-background
// text can end up invisible depending on the active theme. Badges below use
// Modifier::REVERSED instead of an explicit fg+bg pair for exactly that
// reason: it swaps whatever the ambient fg/bg already are, which are
// guaranteed to contrast with each other by definition, regardless of which
// theme is active. MUTED is Gray (ANSI 7 / $fg_alt, the theme's own
// secondary-text color) rather than DarkGray (ANSI 8 / $bg_alt, a
// background shade -- low-contrast as text on every theme this repo ships).
const ACCENT: Color = Color::Cyan;
const MUTED: Color = Color::Gray;
const OK: Color = Color::Green;
const WARN: Color = Color::Red;

pub fn draw(frame: &mut Frame, app: &mut App) {
    let area = frame.area();
    match app.screen {
        Screen::Checklist => {
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Length(3), Constraint::Length(3), Constraint::Min(3), Constraint::Length(3)])
                .split(area);
            draw_title(frame, chunks[0], app);
            draw_tab_bar(frame, chunks[1], app);
            draw_checklist_body(frame, chunks[2], app);
            draw_footer_checklist(frame, chunks[3], app);
        }
        Screen::Progress | Screen::Done => {
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .constraints([Constraint::Length(3), Constraint::Min(3), Constraint::Length(3)])
                .split(area);
            draw_title(frame, chunks[0], app);
            draw_progress(frame, chunks[1], app);
            draw_footer_progress(frame, chunks[2], app);
        }
    }

    if let Some(what) = &app.pending_confirm {
        draw_confirm_popup(frame, area, what);
    }
}

fn draw_tab_bar(frame: &mut Frame, area: Rect, app: &App) {
    let mut spans = Vec::new();
    for (i, cat) in Category::ALL.iter().enumerate() {
        if i > 0 {
            spans.push(Span::raw("  "));
        }
        let checked = app.items.iter().filter(|it| it.category == *cat && it.checked).count();
        let total = app.items.iter().filter(|it| it.category == *cat).count();
        let label = format!(" {} ({checked}/{total}) ", cat.tab_label());
        let style = if i == app.current_tab {
            Style::default().fg(ACCENT).add_modifier(Modifier::REVERSED | Modifier::BOLD)
        } else {
            Style::default().fg(MUTED)
        };
        spans.push(Span::styled(label, style));
    }
    let bar = Paragraph::new(Line::from(spans))
        .block(Block::default().borders(Borders::BOTTOM).border_type(BorderType::Rounded).border_style(Style::default().fg(MUTED)));
    frame.render_widget(bar, area);
}

fn draw_confirm_popup(frame: &mut Frame, area: Rect, what: &str) {
    let popup = centered_rect(area, 70, 9);
    frame.render_widget(ratatui::widgets::Clear, popup);

    let lines = vec![
        Line::from(Span::styled("already exists with different content:", Style::default())),
        Line::from(Span::styled(what.to_string(), Style::default().fg(ACCENT).add_modifier(Modifier::BOLD))),
        Line::from(""),
        Line::from(vec![
            Span::styled(" y ", Style::default().fg(OK).add_modifier(Modifier::REVERSED | Modifier::BOLD)),
            Span::raw(" overwrite (backup first)   "),
            Span::styled(" n ", Style::default().fg(WARN).add_modifier(Modifier::REVERSED | Modifier::BOLD)),
            Span::raw(" skip   "),
            Span::styled(" a ", Style::default().fg(ACCENT).add_modifier(Modifier::REVERSED | Modifier::BOLD)),
            Span::raw(" overwrite all remaining"),
        ]),
    ];
    let dialog = Paragraph::new(lines)
        .alignment(ratatui::layout::Alignment::Center)
        .wrap(Wrap { trim: false })
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default().fg(WARN).add_modifier(Modifier::BOLD))
                .title(" config already exists "),
        );
    frame.render_widget(dialog, popup);
}

fn centered_rect(area: Rect, width_pct: u16, height: u16) -> Rect {
    let width = area.width.saturating_mul(width_pct) / 100;
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let height = height.min(area.height);
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    Rect { x, y, width, height }
}

fn draw_title(frame: &mut Frame, area: Rect, app: &App) {
    let subtitle = match app.screen {
        Screen::Checklist => "select what to install",
        Screen::Progress => "installing...",
        Screen::Done if app.cancelled => "cancelled",
        Screen::Done if app.error_count > 0 => "finished with errors",
        Screen::Done => "done",
    };
    let subtitle_color = match app.screen {
        Screen::Done if app.cancelled || app.error_count > 0 => WARN,
        _ => MUTED,
    };
    let title = Paragraph::new(Line::from(vec![
        Span::styled(
            " dotfiles installer ",
            Style::default().fg(ACCENT).add_modifier(Modifier::REVERSED | Modifier::BOLD),
        ),
        Span::raw(" "),
        Span::styled(subtitle, Style::default().fg(subtitle_color)),
    ]))
    .block(Block::default().borders(Borders::BOTTOM).border_type(BorderType::Rounded));
    frame.render_widget(title, area);
}

/// linutil-style two-pane body: item list on the left, a preview of
/// whatever's highlighted on the right (what it actually does, not just its
/// name) -- everything here belongs to the active tab already, so unlike
/// the old single flat list this needs no section headers.
fn draw_checklist_body(frame: &mut Frame, area: Rect, app: &mut App) {
    let cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(45), Constraint::Percentage(55)])
        .split(area);

    let visible = app.visible_items();

    let title_line = if app.search_active || !app.search_query.is_empty() {
        Line::from(vec![
            Span::styled(" search: ", Style::default().fg(ACCENT).add_modifier(Modifier::BOLD)),
            Span::styled(app.search_query.clone(), Style::default()),
            Span::styled(if app.search_active { "_ " } else { " " }, Style::default().fg(ACCENT)),
        ])
    } else {
        Line::from(Span::styled(format!(" {} ", app.current_tab_category().title()), Style::default().fg(MUTED)))
    };
    let list_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(if app.search_active { ACCENT } else { MUTED }))
        .title(title_line);

    if visible.is_empty() {
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled("  no matches", Style::default().fg(MUTED)))).block(list_block),
            cols[0],
        );
        draw_description_pane(frame, cols[1], None);
        return;
    }

    let list_items: Vec<ListItem> = visible
        .iter()
        .map(|&idx| {
            let item = &app.items[idx];
            let (mark, mark_color) = if item.checked { ("[x]", OK) } else { ("[ ]", MUTED) };
            let text_style = if item.checked { Style::default() } else { Style::default().fg(MUTED) };
            ListItem::new(Line::from(vec![
                Span::styled(mark, Style::default().fg(mark_color).add_modifier(Modifier::BOLD)),
                Span::raw(" "),
                Span::styled(item.label.clone(), text_style),
            ]))
        })
        .collect();

    let selected_pos = visible.iter().position(|&i| i == app.selected);
    let mut state = ListState::default().with_selected(selected_pos);
    let list = List::new(list_items)
        .block(list_block)
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED).fg(ACCENT))
        .highlight_symbol(" > ");
    frame.render_stateful_widget(list, cols[0], &mut state);

    draw_description_pane(frame, cols[1], Some(&app.items[app.selected]));
}

fn draw_description_pane(frame: &mut Frame, area: Rect, item: Option<&crate::items::Item>) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(MUTED))
        .title(" details ");

    let Some(item) = item else {
        frame.render_widget(Paragraph::new("").block(block), area);
        return;
    };

    let mut lines = vec![
        Line::from(Span::styled(item.label.clone(), Style::default().fg(ACCENT).add_modifier(Modifier::BOLD))),
        Line::from(""),
    ];
    for para_line in item.description.split('\n') {
        lines.push(Line::from(para_line.to_string()));
    }
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::styled("status: ", Style::default().fg(MUTED)),
        if item.checked {
            Span::styled("will be installed", Style::default().fg(OK).add_modifier(Modifier::BOLD))
        } else {
            Span::styled("skipped (space to select)", Style::default().fg(MUTED))
        },
    ]));

    let paragraph = Paragraph::new(lines).block(block).wrap(Wrap { trim: false });
    frame.render_widget(paragraph, area);
}

fn draw_footer_checklist(frame: &mut Frame, area: Rect, app: &App) {
    let checked = app.items.iter().filter(|i| i.checked).count();
    let text = Line::from(vec![
        Span::styled(format!(" {checked}/{} ", app.items.len()), Style::default().fg(OK).add_modifier(Modifier::BOLD)),
        Span::styled("selected  ", Style::default().fg(MUTED)),
        Span::styled("home: ", Style::default().fg(MUTED)),
        Span::styled(app.home.display().to_string(), Style::default().fg(ACCENT)),
    ]);
    let hints: &[(&str, &str)] = if app.search_active {
        &[("esc", "cancel"), ("enter", "apply")]
    } else {
        &[
            ("↑/↓ j/k", "move"),
            ("←/→ h/l", "tab"),
            ("space", "toggle"),
            ("a", "all"),
            ("/", "search"),
            ("enter", "install"),
            ("q", "quit"),
        ]
    };
    render_keyhint_footer(frame, area, text, hints);
}

fn draw_footer_progress(frame: &mut Frame, area: Rect, app: &App) {
    let text = match app.screen {
        Screen::Done if app.cancelled => {
            Line::from(Span::styled(" cancelled ", Style::default().fg(WARN).add_modifier(Modifier::BOLD)))
        }
        Screen::Done if app.error_count > 0 => Line::from(vec![
            Span::styled(format!(" {} error(s) ", app.error_count), Style::default().fg(WARN).add_modifier(Modifier::BOLD)),
            Span::styled("-- safe to re-run, anything already done is skipped", Style::default().fg(MUTED)),
        ]),
        Screen::Done if app.skipped_count > 0 => Line::from(vec![
            Span::styled(" done ", Style::default().fg(OK).add_modifier(Modifier::BOLD)),
            Span::styled(format!("-- {} skipped (answered no)", app.skipped_count), Style::default().fg(MUTED)),
        ]),
        Screen::Done => Line::from(Span::styled(" all done ", Style::default().fg(OK).add_modifier(Modifier::BOLD))),
        _ => Line::from(Span::styled(" running... ", Style::default().fg(ACCENT))),
    };
    let hints: &[(&str, &str)] = match app.screen {
        Screen::Done => &[("any key", "quit")],
        _ => &[("esc / ctrl+c", "cancel")],
    };
    render_keyhint_footer(frame, area, text, hints);
}

fn render_keyhint_footer(frame: &mut Frame, area: Rect, left: Line, hints: &[(&str, &str)]) {
    let mut right_spans = Vec::new();
    for (i, (key, desc)) in hints.iter().enumerate() {
        if i > 0 {
            right_spans.push(Span::styled("  ", Style::default()));
        }
        right_spans.push(Span::styled(*key, Style::default().fg(MUTED).add_modifier(Modifier::REVERSED)));
        right_spans.push(Span::raw(" "));
        right_spans.push(Span::styled(*desc, Style::default().fg(MUTED)));
    }
    let block = Block::default().borders(Borders::TOP).border_type(BorderType::Rounded).border_style(Style::default().fg(MUTED));
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let cols = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(inner);
    frame.render_widget(Paragraph::new(left), cols[0]);
    frame.render_widget(Paragraph::new(Line::from(right_spans)).alignment(ratatui::layout::Alignment::Right), cols[1]);
}

fn draw_progress(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(3)])
        .split(area);

    draw_gauge(frame, chunks[0], app);

    let log_area = chunks[1];
    let visible = log_area.height.saturating_sub(2) as usize;
    let start = app.log.len().saturating_sub(visible);
    let lines: Vec<Line> = app.log[start..].iter().map(|l| style_log_line(l)).collect();

    let log = Paragraph::new(lines)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_type(BorderType::Rounded)
                .border_style(Style::default().fg(MUTED))
                .title(" log "),
        )
        .wrap(Wrap { trim: false });
    frame.render_widget(log, log_area);
}

fn style_log_line(line: &str) -> Line<'static> {
    let owned = line.to_string();
    if owned.starts_with("── ") {
        Line::from(Span::styled(owned, Style::default().fg(ACCENT).add_modifier(Modifier::BOLD)))
    } else if owned.contains("ERROR") || owned.starts_with("Cancelled") {
        Line::from(Span::styled(owned, Style::default().fg(WARN).add_modifier(Modifier::BOLD)))
    } else if owned.contains("already up to date") {
        Line::from(Span::styled(owned, Style::default().fg(MUTED)))
    } else {
        Line::from(Span::raw(owned))
    }
}

fn draw_gauge(frame: &mut Frame, area: Rect, app: &App) {
    let ratio = if app.total_steps == 0 {
        0.0
    } else {
        (app.done_steps as f64 / app.total_steps as f64).min(1.0)
    };
    let label = format!("{}/{}", app.done_steps, app.total_steps);
    let color = match app.screen {
        Screen::Done if app.cancelled || app.error_count > 0 => WARN,
        Screen::Done => OK,
        _ => ACCENT,
    };
    let gauge = Gauge::default()
        .block(Block::default().borders(Borders::ALL).border_type(BorderType::Rounded).border_style(Style::default().fg(MUTED)))
        .gauge_style(Style::default().fg(color))
        .ratio(ratio)
        .label(Span::styled(label, Style::default().add_modifier(Modifier::BOLD)));
    frame.render_widget(gauge, area);
}
