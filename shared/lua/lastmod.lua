-- lastmod.lua
function Meta(m)
  -- 0) Varsayılan repo adresi (fallback)
  local DEFAULT_URL = "https://github.com/narineneoldu/narineneoldu.github.io"

  -- 1) Dil
  local lang = pandoc.utils.stringify(m["lang"] or "tr")

  -- 2) Zaman damgaları
  local now_iso_utc = os.date("!%Y-%m-%dT%H:%M:%SZ") -- SEO için ISO 8601 (UTC)
  local t = os.date("!*t") -- {year, month, day, hour, min, ...}

  -- 3) Ay adları (TR/EN)
  local MONTHS = {
    tr = {"Oca","Şub","Mar","Nis","May","Haz","Tem","Ağu","Eyl","Eki","Kas","Ara"},
    en = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
  }
  local month_name = (lang == "en") and MONTHS.en[t.month] or MONTHS.tr[t.month]
  local date_format = (lang == "en") and "%s %02d, %04d" or "%02d %s %04d"
  local date_human
  if lang == "en" then
    date_human = string.format( "%s %02d, %04d", month_name, t.day, t.year)
  else
    date_human = string.format("%02d %s %04d", t.day, month_name, t.year)
  end
  local time_human = string.format("%02d:%02d UTC", t.hour, t.min) -- UTC önerilir

  -- 4) SEO meta (Google: itemprop="dateModified")
  m["date-modified"] = pandoc.MetaString(now_iso_utc)

  -- 5) repo-url (_quarto.yml) -> commits linki
  local base_repo = pandoc.utils.stringify(m["repo-url"] or DEFAULT_URL)
  base_repo = base_repo:gsub("/+$","") -- sondaki /'ları temizle
  local href = base_repo .. "/commits/main/"

  -- 6) Footer metni (dil bazlı)
  local label = (lang == "en") and "Updated on" or "Güncelleme:"
  local html = string.format(
    '<span class="footer-updated">%s<br><a href="%s" target="_blank" rel="noopener">%s, %s</a></span>',
    label, href, date_human, time_human
  )
  m["last-updated-footer"] = pandoc.MetaString(html)

  return m
end
