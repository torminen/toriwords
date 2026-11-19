// Safari share preprocessing: returns the selection, page title, URL and the sentence around
// the selection. The extension treats the presence of this result as "shared from Safari".
var ExtensionPreprocessingJS = {
    run: function (args) {
        var selection = "", sentence = "";
        try {
            var sel = window.getSelection();
            selection = sel ? String(sel) : "";
            if (sel && sel.rangeCount > 0 && selection.trim().length > 0) {
                sentence = sentenceAround(sel.getRangeAt(0), selection);
            }
        } catch (e) {}
        args.completionFunction({ selection: selection, title: document.title || "", url: document.URL || "", sentence: sentence });
    },
    finalize: function (args) {}
};

var BLOCKS = /^(P|LI|TD|TH|DD|DT|DIV|BLOCKQUOTE|H[1-6]|ARTICLE|SECTION|FIGCAPTION|PRE|BODY)$/;
// End of a sentence: . ! ? … with optional closing quotes/brackets, then whitespace.
var END = /[.!?…]["'”’»)\]]*\s/g;

function sentenceAround(range, selection) {
    var block = range.startContainer;
    while (block && (block.nodeType !== 1 || !BLOCKS.test(block.tagName))) { block = block.parentNode; }
    if (!block) { return ""; }
    var before = document.createRange();
    before.setStart(block, 0);
    before.setEnd(range.startContainer, range.startOffset);
    var text = block.textContent || "";
    var start = before.toString().length, end = start + range.toString().length;
    var from = 0, to = text.length, m;
    END.lastIndex = 0;
    while ((m = END.exec(text)) !== null) {
        var boundary = m.index + m[0].length;
        if (boundary <= start) { from = boundary; } else if (m.index + 1 >= end) { to = m.index + m[0].length; break; }
    }
    var out = text.slice(from, to).replace(/\s+/g, " ").trim();
    return out.length > 0 && out.length <= 2000 ? out : "";
}
