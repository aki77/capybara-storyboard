#!/usr/bin/env ruby
# frozen_string_literal: true

# Build a single-file side-by-side (before / after / diff) HTML from reg-cli output.
#
# Usage:
#   ruby build-html.rb [--dir tmp/screenshot-compare] [--notes <dir>/notes.json]
#                      [--title "Screenshot comparison"] [--out <dir>/compare.html]
#
# Reads <dir>/before, <dir>/after, <dir>/diff and <dir>/report.json.
# Exit codes: 0 success, 2 invalid input.

require 'base64'
require 'cgi'
require 'json'
require 'optparse'
require 'pathname'

CSS = <<~CSS
  :root {
    --bg: #f6f7f9; --fg: #1d2330; --muted: #5d6677; --card: #ffffff; --border: #d9dde5;
    --changed: #b45309; --changed-bg: #fef3c7; --new: #1d4ed8; --new-bg: #dbeafe;
    --deleted: #b91c1c; --deleted-bg: #fee2e2; --passed: #4b5563; --passed-bg: #e5e7eb;
    --intended: #166534; --intended-bg: #dcfce7; --regression: #991b1b; --regression-bg: #fecaca;
    --checker: #e9ebef;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #12151b; --fg: #e6e9ef; --muted: #9aa3b2; --card: #1b1f27; --border: #2e3440;
      --changed: #fcd34d; --changed-bg: #422d06; --new: #93c5fd; --new-bg: #172554;
      --deleted: #fca5a5; --deleted-bg: #450a0a; --passed: #cbd5e1; --passed-bg: #2b303a;
      --intended: #86efac; --intended-bg: #052e16; --regression: #fecaca; --regression-bg: #7f1d1d;
      --checker: #252a33;
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 16px 24px 48px; background: var(--bg); color: var(--fg);
    font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  h1 { margin: 0 0 8px; font-size: 22px; }
  h2 { margin: 32px 0 8px; font-size: 16px; font-family: ui-monospace, Menlo, monospace; word-break: break-all; }
  .counts { display: flex; flex-wrap: wrap; gap: 8px; margin: 8px 0; }
  .summary { margin: 12px 0; padding: 10px 14px; background: var(--card);
    border: 1px solid var(--border); border-radius: 6px; white-space: pre-wrap; }
  .badge { display: inline-block; padding: 1px 8px; border-radius: 999px; font-size: 12px; font-weight: 600; }
  .b-changed { color: var(--changed); background: var(--changed-bg); }
  .b-new { color: var(--new); background: var(--new-bg); }
  .b-deleted { color: var(--deleted); background: var(--deleted-bg); }
  .b-passed, .b-noise { color: var(--passed); background: var(--passed-bg); }
  .b-intended { color: var(--intended); background: var(--intended-bg); }
  .b-regression { color: var(--regression); background: var(--regression-bg); }
  .b-unknown { color: var(--muted); background: var(--passed-bg); }
  .row { margin: 8px 0; padding: 10px 12px; background: var(--card);
    border: 1px solid var(--border); border-radius: 6px; }
  .row-head { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; margin-bottom: 8px; }
  .fname { font-family: ui-monospace, Menlo, monospace; font-size: 13px; word-break: break-all; }
  .comment { margin: 0 0 8px; color: var(--muted); white-space: pre-wrap; }
  .cols { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; }
  .col h3 { margin: 0 0 4px; font-size: 12px; color: var(--muted); text-transform: uppercase; }
  .col img { display: block; max-width: 100%; height: auto; border: 1px solid var(--border);
    background: var(--checker); cursor: zoom-in; }
  .col { overflow-x: auto; }
  .none { color: var(--muted); font-style: italic; }
  details > summary { cursor: pointer; color: var(--muted); margin: 8px 0; }
  @media (max-width: 800px) { .cols { grid-template-columns: 1fr; } }
  .lb { position: fixed; inset: 0; z-index: 100; display: flex; flex-direction: column;
    background: rgba(8, 10, 14, 0.85); color: #f1f3f7; }
  .lb[hidden] { display: none; }
  .lb-bar { display: flex; align-items: center; gap: 12px; padding: 8px 16px;
    background: rgba(8, 10, 14, 0.7); border-bottom: 1px solid rgba(255, 255, 255, 0.2); }
  .lb-title { flex: 1; min-width: 0; font: 13px ui-monospace, Menlo, monospace; word-break: break-all; }
  .lb-close { flex: none; width: 32px; height: 32px; border: 1px solid rgba(255, 255, 255, 0.4);
    border-radius: 6px; background: transparent; color: inherit; font-size: 20px; line-height: 1; cursor: pointer; }
  .lb-close:hover, .lb-close:focus-visible { background: rgba(255, 255, 255, 0.2); }
  .lb-body { flex: 1; display: flex; overflow: auto; padding: 16px; }
  .lb-body img { display: block; flex: none; max-width: none; margin: auto; cursor: default;
    background: var(--checker); border: 1px solid var(--border); }
CSS

JS = <<~JS
  (function () {
    var lb = document.getElementById('lb');
    var img = document.getElementById('lb-img');
    var title = document.getElementById('lb-title');
    function close() { lb.hidden = true; img.removeAttribute('src'); }
    document.addEventListener('click', function (e) {
      var t = e.target;
      if (t.tagName === 'IMG' && t !== img && t.src) {
        img.src = t.src;
        img.alt = t.alt;
        title.textContent = t.alt;
        lb.hidden = false;
        lb.querySelector('.lb-body').scrollTo(0, 0);
      } else if (t === lb || t.classList.contains('lb-body') || t.classList.contains('lb-close')) {
        close();
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && !lb.hidden) { close(); }
    });
  })();
JS

# rubocop:disable Metrics/ClassLength
# Reads reg-cli output and renders the self-contained side-by-side HTML.
class CompareBuilder
  # Raised for invalid input (missing directories, broken JSON); mapped to exit code 2.
  class InputError < StandardError; end

  WARN_BYTES = 50 * 1024 * 1024
  STATUS_ORDER = %i[changed new deleted passed].freeze
  VERDICTS = %w[intended regression noise].freeze

  # reg-cli report.json key => status. When a path appears under several keys the later one wins,
  # so the order here is significant (passed < deleted < new < changed).
  REPORT_KEYS = {
    'passedItems' => :passed,
    'deletedItems' => :deleted,
    'newItems' => :new,
    'failedItems' => :changed,
  }.freeze

  Entry =
    Struct.new(:path, :status, :before, :after, :diff, :note) do
      def passed?
        status == :passed
      end

      def changed?
        status == :changed
      end

      # Images that get embedded; an unchanged screen has identical before/after, so only one is kept.
      def images
        passed? ? [after] : [before, after, diff]
      end
    end

  def initialize(dir: 'tmp/screenshot-compare', notes: nil, title: 'Screenshot comparison', out: nil)
    @dir = Pathname(dir)
    @notes_path = Pathname(notes || @dir.join('notes.json'))
    @title = title
    @out = Pathname(out || @dir.join('compare.html'))
    @summary = nil
    @items = {}
  end

  def run
    validate_inputs
    report = load_json(@dir.join('report.json'))
    load_notes
    entries = build_entries(report)
    warn_size(entries)
    @out.dirname.mkpath
    @out.write(render(entries))
    @out.to_s
  end

  private

  def validate_inputs
    raise InputError, "directory not found: #{@dir}" unless @dir.directory?

    %w[before after].each do |name|
      raise InputError, "directory not found: #{@dir.join(name)}" unless @dir.join(name).directory?
    end
    raise InputError, "report.json not found: #{@dir.join('report.json')}" unless @dir.join('report.json').file?
  end

  # Parses a JSON file whose top level must be an object.
  def load_json(path)
    data = JSON.parse(path.read)
    raise InputError, "#{path} must be a JSON object" unless data.is_a?(Hash)

    data
  rescue JSON::ParserError => e
    raise InputError, "failed to parse #{path}: #{e.message}"
  end

  def load_notes
    return unless @notes_path.file?

    data = load_json(@notes_path)
    @summary = data['summary']
    items = data['items'].is_a?(Hash) ? data['items'] : {}
    @items = items.each_with_object({}) { |(k, v), h| h[normalize(k)] = v.is_a?(Hash) ? v : {} }
  end

  def normalize(path)
    path.to_s.sub(%r{\A(?:\./|/)+}, '')
  end

  def build_entries(report)
    states = {}
    REPORT_KEYS.each { |key, status| Array(report[key]).each { |p| states[normalize(p)] = status } }

    states.map do |path, status|
      before = status == :new ? nil : image_path('before', path)
      after = status == :deleted ? nil : image_path('after', path)
      diff = status == :changed ? image_path('diff', diff_name(path)) : nil
      Entry.new(path, status, before, after, diff, @items.fetch(path, {}))
    end
  end

  def diff_name(path)
    path.sub(%r{\.[^./]+\z}, '.png')
  end

  def image_path(kind, rel)
    candidate = @dir.join(kind, rel)
    candidate.file? ? candidate : nil
  end

  # Estimates the base64-embedded size up front; only warns, generation continues.
  def warn_size(entries)
    raw = entries.sum { |e| e.images.compact.sum { |p| File.size(p) } }
    estimated = raw * 4 / 3
    return if estimated <= WARN_BYTES

    mb = (estimated / 1024.0 / 1024).round(1)
    warn "warning: embedded images total #{mb}MB (> 50MB); the HTML may be slow to open"
  end

  def data_uri(path)
    "data:image/png;base64,#{Base64.strict_encode64(path.binread)}"
  end

  def esc(value)
    CGI.escapeHTML(value.to_s)
  end

  def badge(css, text)
    %(<span class="badge b-#{css}">#{esc(text)}</span>)
  end

  def render(entries)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{esc(@title)}</title>
      <style>
      #{CSS}</style>
      </head>
      <body>
      <h1>#{esc(@title)}</h1>
      #{render_counts(entries)}
      #{render_summary}
      #{render_sections(entries)}
      #{render_lightbox}
      <script>
      #{JS}</script>
      </body>
      </html>
    HTML
  end

  def render_lightbox
    <<~HTML.chomp
      <div id="lb" class="lb" hidden role="dialog" aria-modal="true" aria-label="Image viewer">
      <div class="lb-bar"><span id="lb-title" class="lb-title"></span><button type="button" class="lb-close" aria-label="Close">&times;</button></div>
      <div class="lb-body"><img id="lb-img" alt=""></div>
      </div>
    HTML
  end

  def render_counts(entries)
    badges = STATUS_ORDER.map { |s| badge(s, "#{s}: #{entries.count { |e| e.status == s }}") }
    %(<div class="counts">#{badges.join}</div>)
  end

  def render_summary
    return '' if @summary.to_s.strip.empty?

    %(<div class="summary">#{esc(@summary)}</div>)
  end

  def render_sections(entries)
    sections = entries.group_by { |e| File.dirname(e.path) }
    ordered = sections.sort_by { |dir, list| [list.all?(&:passed?) ? 1 : 0, dir] }
    ordered.map { |dir, list| render_section(dir, list.sort_by(&:path)) }.join("\n")
  end

  def render_section(dir, list)
    passed, active = list.partition(&:passed?)
    parts = [%(<section>\n<h2>#{esc(dir)}</h2>)]
    parts.concat(active.map { |e| render_row(e) })
    unless passed.empty?
      parts << %(<details><summary>#{passed.size} unchanged</summary>)
      parts.concat(passed.map { |e| render_row(e) })
      parts << '</details>'
    end
    parts << '</section>'
    parts.join("\n")
  end

  def render_row(entry)
    <<~HTML.chomp
      <div class="row">
      <div class="row-head">#{badge(entry.status, entry.status)}#{verdict_badge(entry.note)}<span class="fname">#{esc(File.basename(entry.path))}</span></div>
      #{comment_html(entry.note)}
      <div class="cols">
      #{render_columns(entry)}
      </div>
      </div>
    HTML
  end

  def render_columns(entry)
    return column('before = after', entry.after, entry.path) if entry.passed?

    before = column('before', entry.before, entry.path)
    after = column('after', entry.after, entry.path)
    "#{before}\n#{after}\n#{column('diff', entry.diff, entry.path, show: entry.changed?)}"
  end

  def comment_html(note)
    text = note['comment'].to_s
    text.empty? ? '' : %(<p class="comment">#{esc(text)}</p>)
  end

  def verdict_badge(note)
    return '' unless note['verdict']

    verdict = note['verdict'].to_s
    badge(VERDICTS.include?(verdict) ? verdict : 'unknown', verdict)
  end

  def column(label, path, rel, show: true)
    return '' unless show

    inner =
      if path
        %(<img src="#{data_uri(path)}" alt="#{esc(label)}: #{esc(rel)}" loading="lazy">)
      else
        '<span class="none">(none)</span>'
      end
    %(<div class="col"><h3>#{esc(label)}</h3>#{inner}</div>)
  end
end
# rubocop:enable Metrics/ClassLength

options = {}
parser =
  OptionParser.new do |o|
    o.banner = 'usage: build-html.rb [options]'
    o.on('--dir DIR', 'directory holding before/ after/ diff/ report.json') { |v| options[:dir] = v }
    o.on('--notes FILE', 'notes.json (default: <dir>/notes.json, ignored if missing)') { |v| options[:notes] = v }
    o.on('--title TITLE', 'page title') { |v| options[:title] = v }
    o.on('--out FILE', 'output html (default: <dir>/compare.html)') { |v| options[:out] = v }
  end

begin
  parser.parse!
  puts CompareBuilder.new(**options).run
rescue CompareBuilder::InputError, OptionParser::ParseError => e
  warn "error: #{e.message}"
  exit(2)
end
