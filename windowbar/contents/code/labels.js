.pragma library

// Window-title -> short label logic.
//
// Goal: for windows of the same app, show only the part of the title that
// tells them apart. E.g. three Konsole windows titled
//   user@host: ~/src/shop              -> "shop"
//   user@host: ~/src/shop/api          -> "shop/api"
//   user@host: ~/src/robot/firmware    -> "robot/firmware"

// Separators we split titles on. Kept as tokens so labels can be rebuilt.
var DELIM = /(\s+[—–\-|·:]\s+|:\s+|\/)/;
var DELIM_ONLY = /^(\s+[—–\-|·:]\s+|:\s+|\/)$/;

function isDelim(tok) { return DELIM_ONLY.test(tok); }

// Strip the trailing " — AppName" (Konsole, Dolphin, Firefox all add one)
// and a shell's "user@host: " prefix.
function cleanTitle(title, appName) {
    var t = String(title || "");
    var m = t.match(/^(.*\S)\s+[—–-]\s+([^—–]+)$/);
    if (m && appName) {
        var tail = m[2].toLowerCase(), app = String(appName).toLowerCase();
        if (tail.indexOf(app) !== -1 || app.indexOf(tail) !== -1) t = m[1];
    }
    t = t.replace(/^[^@\s]+@[^:\s]+:\s*/, "");
    return t.trim();
}

function tokenize(s) {
    return s.split(DELIM).filter(function (x) { return x !== ""; });
}

function prefixLen(a, b) {
    var n = Math.min(a.length, b.length), i = 0;
    while (i < n && a[i] === b[i]) i++;
    return i;
}

function suffixLen(a, b, limitA, limitB) {
    var i = 0;
    while (i < a.length - limitA && i < b.length - limitB
           && a[a.length - 1 - i] === b[b.length - 1 - i]) i++;
    return i;
}

function trimDelims(toks) {
    var s = 0, e = toks.length;
    while (s < e && isDelim(toks[s])) s++;
    while (e > s && isDelim(toks[e - 1])) e--;
    return toks.slice(s, e).join("").trim();
}

// Index of the start of the last non-delimiter token before position p.
function backOff(toks, p) {
    var i = p - 1;
    while (i >= 0 && isDelim(toks[i])) i--;
    return Math.max(0, i);
}

// titles: array of already-cleaned titles. Returns an array of labels.
function distinguish(titles) {
    var toks = titles.map(tokenize);
    return toks.map(function (t, i) {
        var p = 0, s = 0;
        for (var j = 0; j < toks.length; j++) {
            if (j === i) continue;
            p = Math.max(p, prefixLen(t, toks[j]));
        }
        // Keep one token of context when we'd otherwise start right after a
        // shared parent ("shop/api" rather than "api"), or when the
        // whole title is shared.
        if (p > 0 && (p >= t.length || isDelim(t[p]))) p = backOff(t, p);
        for (j = 0; j < toks.length; j++) {
            if (j === i) continue;
            var pj = prefixLen(t, toks[j]);
            s = Math.max(s, suffixLen(t, toks[j], p, pj));
        }
        var label = trimDelims(t.slice(p, t.length - s));
        return label || titles[i];
    });
}
