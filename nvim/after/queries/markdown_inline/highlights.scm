;; extends
; "- [!] text": tree-sitter only knows [ ] and [x] as task markers, so [!] is
; parsed as a shortcut_link. Capture it when it starts the item's text, so it
; stays red without render-markdown (insert mode). Linked in notes/init.lua.
((inline
  .
  (shortcut_link
    (link_text) @_state) @markup.list.important) @_text
  (#eq? @_state "!")
  (#lua-match? @_text "^%[!%]")
  (#set! priority 110))
