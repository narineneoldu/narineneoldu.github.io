// date_modified.js
document.addEventListener("DOMContentLoaded", function () {
  // --- 1. Find the ISO timestamp from meta tag ---
  const meta = document.querySelector('meta[itemprop="dateModified"]');
  if (!meta) return;

  const iso = meta.getAttribute("content"); // e.g. 2025-12-09T00:46:44Z
  const modified = new Date(iso);
  if (isNaN(modified)) return;

  // --- 2. Compute time differences in various units ---
  let diffMs = Date.now() - modified.getTime();
  if (diffMs < 0) diffMs = 0; // guard against future timestamps

  const diffSec   = diffMs   / 1000;
  const diffMin   = diffSec  / 60;
  const diffHour  = diffMin  / 60;
  const diffDay   = diffHour / 24;
  const diffWeek  = diffDay  / 7;
  const diffMonth = diffDay  / 30;
  const diffYear  = diffDay  / 365;

  // --- 3. Load i18n data from <head> (with English fallback) ---

  // Built-in English defaults (keys must match those in js_data)
  const defaultI18n = {
    "date_style": "medium",
    "time_style": "short",
    "ago-just-now": "just now",
    "ago-minute": "{n} minute ago",
    "ago-minutes": "{n} minutes ago",
    "ago-hour": "{n} hour ago",
    "ago-hours": "{n} hours ago",
    "ago-day": "{n} day ago",
    "ago-days": "{n} days ago",
    "ago-week": "{n} week ago",
    "ago-weeks": "{n} weeks ago",
    "ago-month": "{n} month ago",
    "ago-months": "{n} months ago",
    "ago-year": "{n} year ago",
    "ago-years": "{n} years ago"
  };

  /**
   * Read i18n JSON from <script id="date-modified-i18n" type="application/json">
   * and merge it on top of defaultI18n. On any error, defaultI18n is used.
   */
  function loadI18n() {
    const script = document.getElementById("date-modified-i18n");
    if (!script) {
      return { ...defaultI18n };
    }
    try {
      const raw = script.textContent || script.innerText || "";
      if (!raw.trim()) {
        return { ...defaultI18n };
      }
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object") {
        return { ...defaultI18n };
      }
      // Merge: user-provided i18n overrides defaults
      return { ...defaultI18n, ...parsed };
    } catch (e) {
      // On any parse error, fall back to default English
      return { ...defaultI18n };
    }
  }

  const i18n = loadI18n();

  // --- 4. Helpers to format relative strings using i18n templates ---

  /**
   * Replace "{n}" placeholder in a pattern with the given number.
   * Returns the input pattern unchanged if it is missing or not a string.
   */
  function applyNumber(pattern, n) {
    if (typeof pattern !== "string") return pattern || "";
    return pattern.replace("{n}", String(n));
  }

  /**
   * Safely fetch i18n pattern by key, falling back to defaultI18n if needed.
   */
  function getPattern(key) {
    if (Object.prototype.hasOwnProperty.call(i18n, key)) {
      return i18n[key];
    }
    return defaultI18n[key] || "";
  }

  /**
   * Build relative "time ago" text based on the elapsed time buckets.
   * Uses i18n patterns for singular/plural, inserting the numeric value via {n}.
   */
  function buildRelativeText() {
    if (diffMin < 1) {
      // just now
      return getPattern("ago-just-now");
    } else if (diffHour < 1) {
      // minutes
      const m = Math.floor(diffMin);
      const key = (m === 1) ? "ago-minute" : "ago-minutes";
      return applyNumber(getPattern(key), m);
    } else if (diffHour < 24) {
      // hours
      const h = Math.floor(diffHour);
      const key = (h === 1) ? "ago-hour" : "ago-hours";
      return applyNumber(getPattern(key), h);
    } else if (diffDay < 7) {
      // days
      const d = Math.floor(diffDay);
      const key = (d === 1) ? "ago-day" : "ago-days";
      return applyNumber(getPattern(key), d);
    } else if (diffWeek < 4) {
      // weeks
      const w = Math.floor(diffWeek);
      const key = (w === 1) ? "ago-week" : "ago-weeks";
      return applyNumber(getPattern(key), w);
    } else if (diffMonth < 12) {
      // months
      const m = Math.floor(diffMonth);
      const key = (m === 1) ? "ago-month" : "ago-months";
      return applyNumber(getPattern(key), m);
    } else {
      // years
      const y = Math.floor(diffYear);
      const key = (y === 1) ? "ago-year" : "ago-years";
      return applyNumber(getPattern(key), y);
    }
  }

  const relativeText = buildRelativeText();

  // --- 5. Update all .date-modified-value spans on the page ---

  const valueSpans = document.querySelectorAll(".date-modified-value");
  if (!valueSpans.length) return; // nothing to update

  // We no longer use lang for choosing strings, only for date/time locale.
  const htmlLang = document.documentElement.lang || "en-US";
  const locale = htmlLang || "en-US";

  valueSpans.forEach(valueSpan => {
    // Infer whether original text had a time component (HH:MM)
    const rawText = valueSpan.textContent || "";
    const hasTime = /\d{1,2}:\d{2}/.test(rawText);
    const hideTime = !hasTime;

    // Build localized date/time tooltip using browser locale
    let localDateTime;
    if (hideTime) {
      // Only date in tooltip if original value had no time component
      localDateTime = modified.toLocaleDateString(locale, {
        dateStyle:  i18n.date_style,
      });
    } else {
      // Date + time if original value contained time
      localDateTime = modified.toLocaleString(locale, {
        dateStyle: i18n.date_style,
        timeStyle: i18n.time_style,
      });
    }

    // Apply relative text + tooltip
    const innerLink = valueSpan.querySelector("a");
    if (innerLink) {
      innerLink.textContent = relativeText;
    } else {
      valueSpan.textContent = relativeText;
    }
    valueSpans.forEach(span => {
      span.setAttribute("data-title", localDateTime);
    });
  });
});
