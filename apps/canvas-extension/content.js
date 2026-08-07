// CerebralHelm Canvas Sync — content script, runs on Canvas pages (NIC-132).
//
// Reads the *new* Canvas dashboard and posts { sourceUrl, courses, deadlines } to the background
// worker (which adds the token + endpoint). It scrapes only when the dashboard widgets are actually
// present, so browsing a deep course page never clobbers the stored scrape with an empty one.
//
// Selectors: the new dashboard exposes stable `data-testid`s (Instructure keeps these for their own
// tests), which is why this is far sturdier than a class-based scrape. The courses/grades + empty
// states are confirmed against a live dashboard; the populated upcoming-assignment row shape is the
// one piece to confirm once a real course load exists (see scrapeDeadlines) — it is isolated here,
// behind the frozen ingest payload, so tuning it never touches CerebralHelm.

console.debug("[CerebralHelm Canvas Sync] content script loaded:", location.href);

const DASHBOARD_SELECTOR =
  '[data-testid="widget-course-grades-widget"], [data-testid="widget-course-work-combined-widget"]';

/** The trimmed text of a `data-testid` element, or undefined when absent/blank. */
function textOf(testid) {
  const element = document.querySelector(`[data-testid="${testid}"]`);
  if (!element) return undefined;
  const text = element.textContent.replace(/\s+/g, " ").trim();
  return text.length > 0 ? text : undefined;
}

/**
 * Parse the grade cell text into `{ percent?, letterGrade?, gradeHidden }`. Canvas shows a percent,
 * a letter, both, "N/A" (no graded work), or a hidden marker. Nothing is fabricated — an absent
 * figure stays undefined, and CerebralHelm never fills a ring for a hidden grade.
 */
function parseGrade(text) {
  const trimmed = (text || "").trim();
  if (!trimmed || /^n\/a$/i.test(trimmed)) {
    return { percent: undefined, letterGrade: undefined, gradeHidden: false };
  }
  if (/hidden/i.test(trimmed)) {
    return { percent: undefined, letterGrade: undefined, gradeHidden: true };
  }
  const percentMatch = trimmed.match(/(\d+(?:\.\d+)?)\s*%/);
  const letterMatch = trimmed.match(/\b([A-F][+-]?)\b/);
  return {
    percent: percentMatch ? Number(percentMatch[1]) : undefined,
    letterGrade: letterMatch ? letterMatch[1] : undefined,
    gradeHidden: false
  };
}

/** Current courses + grades from the Course grades widget (confirmed testids). */
function scrapeCourses() {
  const courses = [];
  for (const card of document.querySelectorAll('[data-testid^="course-grade-card-"]')) {
    const testid = card.getAttribute("data-testid") || "";
    const id = testid.replace("course-grade-card-", "");
    if (!id) continue;
    const name = textOf(`course-${id}-name`) || textOf(`course-${id}-code`);
    if (!name) continue; // a card without a readable name is skipped, never fabricated
    const grade = parseGrade(textOf(`course-${id}-grade`));
    courses.push({
      id,
      name,
      code: textOf(`course-${id}-code`),
      percent: grade.percent,
      letterGrade: grade.letterGrade,
      gradeHidden: grade.gradeHidden,
      url: `${location.origin}/courses/${id}`
    });
  }
  return courses;
}

/** Convert an ISO instant to a LOCAL wall-clock `yyyy-MM-ddTHH:mm:ss` — CerebralHelm's formatters
 *  slice the time components directly (no timezone conversion), so the string must already be local. */
function localWallClock(iso) {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return undefined;
  const pad = (value) => String(value).padStart(2, "0");
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
  );
}

/** True when an upcoming-work row looks submitted or completed (excluded per the ticket). */
function isSubmittedOrComplete(row) {
  if (row.querySelector('[data-testid*="submitted" i], [aria-label*="submitted" i], [aria-label*="complete" i]')) {
    return true;
  }
  return /\bsubmitted\b|\bcompleted\b/i.test(row.textContent || "");
}

/**
 * Upcoming assignments from the Course work widget.
 *
 * FALL-TUNABLE: the empty state (`no-course-work-message`) is confirmed, but the populated row's
 * exact markup wasn't observable off-season, so this reads it defensively — each upcoming item links
 * to its assignment/quiz/discussion, so we collect those links, take the title from the link, the due
 * date from a nested `<time datetime>`, and drop anything marked submitted/completed. Confirm/adjust
 * against a real course load; nothing downstream changes because the payload shape is frozen.
 */
function scrapeDeadlines() {
  const widget = document.querySelector('[data-testid="widget-course-work-combined-widget"]');
  if (!widget) return [];
  if (widget.querySelector('[data-testid="no-course-work-message"]')) return []; // confirmed empty state

  const deadlines = [];
  const seen = new Set();
  const links = widget.querySelectorAll(
    'a[href*="/assignments/"], a[href*="/quizzes/"], a[href*="/discussion_topics/"]'
  );
  for (const link of links) {
    const href = link.getAttribute("href") || "";
    if (!href || seen.has(href)) continue;
    const row = link.closest("li, [data-testid], div") || link;
    if (isSubmittedOrComplete(row)) continue;
    const title = link.textContent.replace(/\s+/g, " ").trim();
    if (!title) continue;
    seen.add(href);
    const time = row.querySelector("time[datetime]");
    deadlines.push({
      id: href,
      title,
      dueAt: time ? localWallClock(time.getAttribute("datetime")) : undefined,
      url: link.href
    });
  }
  return deadlines;
}

/**
 * Read the current dashboard into `{ sourceUrl, courses, deadlines }`, or null when this page isn't
 * the dashboard (so we never post an empty scrape from a course page and wipe the stored data). An
 * empty-but-present dashboard (nothing enrolled/due) is a real result and IS posted.
 */
function scrapeDashboard() {
  if (!document.querySelector(DASHBOARD_SELECTOR)) return null;
  return {
    sourceUrl: location.href,
    courses: scrapeCourses(),
    deadlines: scrapeDeadlines()
  };
}

/** Post a scrape to the background worker (which adds the token + endpoint). */
function sendScrape(scrape) {
  if (!scrape) return;
  chrome.runtime.sendMessage({ type: "canvas-scrape", scrape }).catch(() => {
    // The worker may be asleep; a later visit/interval retries. Nothing to surface on the page.
  });
}

/** The new dashboard renders client-side, so the widgets appear after load — poll briefly for them,
 *  then invoke `callback`. Gives up quietly after ~8s (this page just isn't the dashboard). */
function onDashboardReady(callback) {
  if (document.querySelector(DASHBOARD_SELECTOR)) {
    callback();
    return;
  }
  let attempts = 0;
  const timer = setInterval(() => {
    attempts += 1;
    if (document.querySelector(DASHBOARD_SELECTOR)) {
      clearInterval(timer);
      callback();
    } else if (attempts >= 20) {
      clearInterval(timer);
    }
  }, 400);
}

// Scrape once the dashboard is rendered (fires on a Canvas visit/login landing).
onDashboardReady(() => sendScrape(scrapeDashboard()));

// Re-scrape periodically while this dashboard tab stays open (owner: refresh in the background every
// now and then). A no-op if the user has SPA-navigated away from the dashboard (no widgets → null).
setInterval(() => sendScrape(scrapeDashboard()), 5 * 60 * 1000);
