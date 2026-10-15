// A Markdown checklist (`- [ ] step`) renders as disabled checkboxes with no label, which a screen reader
// announces without the text beside them. labelTaskItems(html) wraps each item whose content is inline
// in a <label>, so the box is named by its own text. An item holding a nested list or paragraphs stays
// as it is.

/** @param {string} html */
export const labelTaskItems = (html) =>
  html.replace(/<li class="task-list-item">(<input type="checkbox"[^>]*>)([\s\S]*?)<\/li>/g, (whole, box, rest) =>
    /<(?:ul|ol|p|div|pre|li)\b/.test(rest) ? whole : `<li class="task-list-item"><label>${box}${rest}</label></li>`,
  );
