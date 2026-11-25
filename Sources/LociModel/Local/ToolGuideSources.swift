extension ToolGuide {
  /// `loci help sources`: sources the app fetches by itself, and the chart rows that show them.
  static let sources = """
    A source is something the app fetches for you, with no model in the way: prices, premiums, net values,
    versions, fares, rates, weather. Its numbers go straight into panel rows, so they are never yours to
    retype, and they stay fresh between refreshes.

    - Make one when a panel would show numbers that change on their own. Look the site's API up first.
    - The app fetches it every <every> while the window is in front, at most hourly while it is behind, and
      only --between those hours. You are never woken for it, except to mend it.
    - Write one script and save it with "$LOCI" source save <name> --title <title> --every <1m|15m|1h>
      [--between HH:mm-HH:mm] [--weekdays] < script.js. The app runs it once at once; it is saved only when
      that works, and you hear what it got. Say in one sentence what it fetched.
    - When it breaks, change the script and run "$LOCI" source test <name> --script < script.js: it runs on
      the responses kept from earlier fetches, without the network. Save it once every sample works. When
      parse fails three times in a row, the app asks you to mend it in the background, with what it failed on.
    - A source only reads: GET with no cookies. Never put the person's name, email or account in a request.

    The script declares two functions; md5(text) and sha1(text) give hex digests, and nothing else is there:
    no network, no storage, nothing from the last run. It is stopped after 3 seconds.

      function requests(state) {
        return [{ url: "https://qt.gtimg.cn/q=sh513870,sh159501", referer: "https://gu.qq.com/",
                  encoding: "gbk" }];
      }
      function parse(responses, now) {
        const records = {};
        for (const line of responses[0].text.split(";")) {
          const f = line.split("~");
          if (f.length < 80) continue;
          records[f[2]] = { name: f[1], price: Number(f[3]), change: Number(f[32]) / 100,
                            premium: Number(f[77]) / 100 };
        }
        return { records, state: { at: now.getTime() } };
      }

    - requests(state) returns links, or { url, referer, userAgent, encoding: "gbk" }; at most 20.
      state is what parse returned last time, or null.
    - { page: "https://…" } reads a page as `loci read` does, signed in when the person connected its site;
      { connector: "github", tool: "gh", arguments: { args: ["api", "repos/o/r/releases"] } } calls a
      connector's read-only tool. Their text comes to parse as a response like any other.
    - parse(responses, now) gets [{ url, status, text }] and now as a Date, and returns
      { records: { <record>: { <field>: value } }, state }. A value is a number, text,
      points [[ms, value], ...] or candles [[ms, open, high, low, close], ...]. Names of records and fields
      use letters, digits, _ and -.
    - Write shares as fractions: 0.159 is 15.9%, -0.0186 is −1.86%.
    - For a list of things that come and go, such as news, papers or issues, parse also returns
      entries: [{ id, title, url, at, note }], at in milliseconds, at most 200. A panel with
      "feed": { "source": "<name>", "skip": ["<word>", ...] } and no refresh follows them: when the source
      reads entries it never had and no skipped word is in their titles, you are shown only those, and keep
      some with "$LOCI" panel pick <panel> --say <sentence> <id>...; the app writes each one's link and time.

    Chart rows draw numbers. Anywhere a number goes, write it, or point at a source's field as
    "<source>.<record>.<field>"; a word that comes from a source is { "field": "<source>.<record>.<field>" }.
    A panel may start with a chart instead of a sentence. Red is up and green is down.

      { "row": "quotes", "quotes": [{ "name": "纳指100 QDII", "code": "513100", "price": "q.513100.price",
        "change": "q.513100.change", "spark": "q.513100.day", "asOf": { "field": "q.513100.date" },
        "digits": 3 }] }
      { "row": "line", "value": "ndx.ndx.price", "change": "ndx.ndx.change", "series": "ndx.ndx.price",
        "digits": 0 }
      { "row": "ruler", "label": "市盈率 · 近五年分位", "value": 31.4, "share": 0.72, "low": 22.1,
        "high": 36.8, "digits": 1 }
      { "row": "allocation", "total": 61.8, "unit": "万", "change": -0.0091, "slices": [
        { "name": "纳指100", "actual": 0.58, "target": 0.6 }] }
      { "row": "heat", "tiles": [{ "code": "NVDA", "weight": 3, "change": -0.059 }] }
      { "row": "candles", "series": "k.300308.daily", "lines": [{ "name": "止盈", "price": 172, "kind": "take" },
        { "name": "止损", "price": 138, "kind": "stop" }] }
      { "row": "zones", "stops": [0, 0.03, 0.1, 0.2], "format": "percent", "values": [
        { "name": "513870", "note": "你持有", "value": "prem.513870.premium" }] }

    - quotes: change is a fraction; spark is a points field; asOf is the net value's date for a fund.
    - line: "series" is a points field, or a number field whose history the app keeps; or "ranges" names a
      field for each span it has: { "1d": …, "5d": …, "1m": …, "1y": …, "5y": … }.
    - ruler: share is where the value stands, 0 at low and 1 at high. allocation: actual and target are
      fractions; a slice more than "tolerance" (0.01) off its target is marked.
    - heat: tiles are sized by weight and coloured by change. candles: "series" is a candles field.
    - "format": "percent" writes fractions as percents; "digits" the places after the point, 0 to 6; "unit"
      a word after the number.
    """
}
