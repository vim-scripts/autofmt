" Maintainer:   Yukihiro Nakadaira <yukihiro.nakadaira@gmail.com>
" License:      This file is placed in the public domain.
" Last Change:  2007-07-02
"
" Options:
"
"   autofmt_allow_over_tw               number (default: 0)
"
"     Allow character, prohibited a line break before, to over 'textwidth'
"     only given width.
"
"
"   autofmt_allow_over_tw_char          string (default: see below)
"
"     Character, prohibited a line break before.  This variable is used with
"     autofmt_allow_over_tw.
"

scriptencoding utf-8

let s:cpo_save = &cpo
set cpo&vim

function autofmt#japanese#formatexpr()
  return s:lib.formatexpr()
endfunction

function autofmt#japanese#import()
  return s:lib
endfunction

function autofmt#japanese#test()
  call s:lib.test()
endfunction

let s:compat = autofmt#compat#import()
let s:uax14 = autofmt#uax14#import()

let s:lib = {}
call extend(s:lib, s:compat)

let s:lib.autofmt_allow_over_tw = 0

let s:lib.autofmt_allow_over_tw_char = ""
      \ . ",)]}、〕〉》」』】〙〗〟’”⦆»"
      \ . "ヽヾーァィゥェォッャュョヮヵヶゝゞぁぃぅぇぉっゃゅょゃゎゕゖ々"
      \ . "‐゠–〜"
      \ . "?!‼⁇⁈⁉"
      \ . "・:;"
      \ . "。."
      \ . "°′″，．：；？！）］｝…～"

function! s:lib.check_boundary(lst, i)
  let [lst, i] = [a:lst, a:i]
  let tw = &textwidth + self.get_opt("autofmt_allow_over_tw")
  let tw_char = self.get_opt("autofmt_allow_over_tw_char")
  if &textwidth < lst[i].virtcol && lst[i].virtcol <= tw
    " Dangling wrap.  Allow character, prohibited a line break before, to
    " over 'textwidth'.
    if stridx(tw_char, lst[i].c) != -1
      return "no_break"
    endif
  endif
  " use compat for single byte text
  if len(lst[i - 1].c) == 1 && len(lst[i].c) == 1
    return s:compat.check_boundary(lst, i)
  endif
  " Overrule UAX #14 table.
  if lst[i - 1].c =~ '[、。]'
    " Japanese punctuation can break a line after that.
    " (、|。) ÷ A
    return "allow_break"
  endif
  " use UAX #14 as default
  return s:uax14.check_boundary(lst, i)
endfunction

function! s:lib.join_line(line1, line2)
  if matchstr(a:line1, '.$') =~ '[、。]'
    " Don't insert space after Japanese punctuation.
    return a:line1 . a:line2
  endif
  return call(s:compat.join_line, [a:line1, a:line2], self)
endfunction

function! s:lib.get_paragraph(lines)
  let para = call(s:compat.get_paragraph, [a:lines], self)
  let i = 0
  while i < len(para)
    let [lnum, lines] = para[i]
    let j = 1
    while j < len(lines)
      if lines[j] =~ '^　' || self.parse_leader(lines[j])[3] =~ '^　'
        " U+3000 at start of line means new paragraph.  split this paragraph.
        call insert(para, [para[i][0], remove(para[i][1], 0, j - 1)], i)
        let i += 1
        let para[i][0] += j
        let j = 1
      else
        let j += 1
      endif
    endwhile
    let i += 1
  endwhile
  return para
endfunction

function! s:lib.test()
  new

  let b:autofmt = self
  setl formatexpr=b:autofmt.formatexpr()
  set debug=msg
  setl textwidth=10 formatoptions=tcnr formatlistpat& comments&
  setl tabstop& shiftwidth& softtabstop& expandtab&
  let b:autofmt_allow_over_tw = self.autofmt_allow_over_tw
  let b:autofmt_allow_over_tw_char = self.autofmt_allow_over_tw_char

  let start = reltime()

  call self.do_test("test1",
        \ "あいう",
        \ ["あいう"])
  call self.do_test("test2",
        \ "あいうえお",
        \ ["あいうえお"])
  call self.do_test("test3",
        \ "あいうえおか",
        \ ["あいうえお", "か"])
  call self.do_test("test4",
        \ "あいうえお。かきくけこ",
        \ ["あいうえ", "お。かきく", "けこ"])
  call self.do_test("test5",
        \ "あいうえ「お",
        \ ["あいうえ", "「お"])
  call self.do_test("test6",
        \ "  あいうえお",
        \ ["  あいうえ", "  お"])
  call self.do_test("test7",
        \ "aaaaa bbbbあいうえお",
        \ ["aaaaa bbbb", "あいうえお"])
  call self.do_test("test8",
        \ "あいうえおaaa",
        \ ["あいうえお", "aaa"])
  call self.do_test("test9",
        \ "あああああいいいいいううううう\<Up>\<Del>\<Up>\<Del>\<Left>えええ",
        \ ["ああああえ", "ええあいいいいいううううう"])
  call self.do_test("test10",
        \ "          ああ",
        \ ["          あ", "          あ"])
  call self.do_test("test11",
        \ "          あ。",
        \ ["          あ。"])
  call self.do_test("test12",
        \ ["ああああ。。いいい"],
        \ ["ああああ。", "。いいい"])

  let b:autofmt_allow_over_tw = 2

  call self.do_test("test13",
        \ ["あああああ。いいい"],
        \ ["あああああ。", "いいい"])

  echo reltimestr(reltime(start))
endfunction

let &cpo = s:cpo_save

