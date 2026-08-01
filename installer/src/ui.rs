use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, Gauge, List, ListItem, ListState, Paragraph, Wrap};

use crate::app::{App, Row, Screen};

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
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(3), Constraint::Length(3)])
        .split(area);

    draw_title(frame, chunks[0], app);
    match app.screen {
        Screen::Checklist => {
            draw_checklist(frame, chunks[1], app);
            draw_footer_checklist(frame, chunks[2], app);
        }
        Screen::Progress | Screen::Done => {
            draw_progress(frame, chunks[1], app);
            draw_footer_progress(frame, chunks[2], app);
        }
    }

    if let Some(what) = &app.pending_confirm {
        draw_confirm_popup(frame, area, what);
    }
}

fn draw_confirm_popup(frame: &mut Frame, area: Rect, what: &str) {
    let popup = centered_rect(area, 70, 9);
    frame.render_widget(ratatui::widgets::Clear, popup);

    let lines = vec![
        Line::from(Span::styled("sudah ada dan isinya beda:", Style::default())),
        Line::from(Span::styled(what.to_string(), Style::default().fg(ACCENT).add_modifier(Modifier::BOLD))),
        Line::from(""),
        Line::from(vec![
            Span::styled(" y ", Style::default().fg(OK).add_modifier(Modifier::REVERSED | Modifier::BOLD)),
            Span::raw(" timpa (backup dulu)   "),
            Span::styled(" n ", Style::default().fg(WARN).add_modifier(Modifier::REVERSED | Modifier::BOLD)),
            Span::raw(" lewati   "),
            Span::styled(" a ", Style::default().fg(ACCENT).add_modifier(Modifier::REVERSED | Modifier::BOLD)),
            Span::raw(" timpa semua sisanya"),
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
                .title(" config sudah ada "),
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
        Screen::Checklist => "pilih apa yang mau di-install",
        Screen::Progress => "menginstall...",
        Screen::Done if app.cancelled => "dibatalkan",
        Screen::Done if app.error_count > 0 => "selesai dengan error",
        Screen::Done => "selesai",
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

fn draw_checklist(frame: &mut Frame, area: Rect, app: &mut App) {
    let visible = app.visible_rows();
    let no_matches = visible.is_empty();

    let list_items: Vec<ListItem> = visible
        .iter()
        .map(|&row_idx| match &app.rows[row_idx] {
            Row::Header(cat) => ListItem::new(Line::from(vec![Span::styled(
                format!(" {}", cat.title()),
                Style::default().fg(ACCENT).add_modifier(Modifier::BOLD | Modifier::UNDERLINED),
            )])),
            Row::Item(idx) => {
                let item = &app.items[*idx];
                let (mark, mark_color) = if item.checked { ("[x]", OK) } else { ("[ ]", MUTED) };
                let text_style = if item.checked { Style::default() } else { Style::default().fg(MUTED) };
                ListItem::new(Line::from(vec![
                    Span::raw("   "),
                    Span::styled(mark, Style::default().fg(mark_color).add_modifier(Modifier::BOLD)),
                    Span::raw(" "),
                    Span::styled(item.label.clone(), text_style),
                ]))
            }
        })
        .collect();

    let selected_pos = visible.iter().position(|&i| i == app.selected);
    let title_line = if app.search_active || !app.search_query.is_empty() {
        Line::from(vec![
            Span::styled(" cari: ", Style::default().fg(ACCENT).add_modifier(Modifier::BOLD)),
            Span::styled(app.search_query.clone(), Style::default()),
            Span::styled(if app.search_active { "_ " } else { " " }, Style::default().fg(ACCENT)),
        ])
    } else {
        Line::from(Span::styled(" semua item (/ untuk cari) ", Style::default().fg(MUTED)))
    };

    let block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(if app.search_active { ACCENT } else { MUTED }))
        .title(title_line);

    if no_matches {
        let msg = Paragraph::new(Line::from(Span::styled(
            "  gak ada yang cocok",
            Style::default().fg(MUTED),
        )))
        .block(block);
        frame.render_widget(msg, area);
        return;
    }

    let mut state = ListState::default().with_selected(selected_pos);
    let list = List::new(list_items)
        .block(block)
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED).fg(ACCENT))
        .highlight_symbol(" > ");
    frame.render_stateful_widget(list, area, &mut state);
}

fn draw_footer_checklist(frame: &mut Frame, area: Rect, app: &App) {
    let checked = app.items.iter().filter(|i| i.checked).count();
    let text = Line::from(vec![
        Span::styled(format!(" {checked}/{} ", app.items.len()), Style::default().fg(OK).add_modifier(Modifier::BOLD)),
        Span::styled("dipilih  ", Style::default().fg(MUTED)),
        Span::styled("home: ", Style::default().fg(MUTED)),
        Span::styled(app.home.display().to_string(), Style::default().fg(ACCENT)),
    ]);
    let hints: &[(&str, &str)] = if app.search_active {
        &[("esc", "batal"), ("enter", "terapkan")]
    } else {
        &[("↑/↓ j/k", "gerak"), ("space", "toggle"), ("a", "semua"), ("/", "cari"), ("enter", "install"), ("q", "keluar")]
    };
    render_keyhint_footer(frame, area, text, hints);
}

fn draw_footer_progress(frame: &mut Frame, area: Rect, app: &App) {
    let text = match app.screen {
        Screen::Done if app.cancelled => {
            Line::from(Span::styled(" dibatalkan ", Style::default().fg(WARN).add_modifier(Modifier::BOLD)))
        }
        Screen::Done if app.error_count > 0 => Line::from(vec![
            Span::styled(format!(" {} error ", app.error_count), Style::default().fg(WARN).add_modifier(Modifier::BOLD)),
            Span::styled("-- aman jalankan lagi, yang sudah beres di-skip", Style::default().fg(MUTED)),
        ]),
        Screen::Done if app.skipped_count > 0 => Line::from(vec![
            Span::styled(" selesai ", Style::default().fg(OK).add_modifier(Modifier::BOLD)),
            Span::styled(format!("-- {} dilewati (jawaban: tidak)", app.skipped_count), Style::default().fg(MUTED)),
        ]),
        Screen::Done => Line::from(Span::styled(" semua berhasil ", Style::default().fg(OK).add_modifier(Modifier::BOLD))),
        _ => Line::from(Span::styled(" sedang berjalan... ", Style::default().fg(ACCENT))),
    };
    let hints: &[(&str, &str)] = match app.screen {
        Screen::Done => &[("tombol apa saja", "keluar")],
        _ => &[("esc / ctrl+c", "batalkan")],
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
    } else if owned.contains("ERROR") || owned.starts_with("Dibatalkan") {
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
