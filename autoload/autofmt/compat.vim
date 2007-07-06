" Maintainer:   Yukihiro Nakadaira <yukihiro.nakadaira@gmail.com>
" License:      This file is placed in the public domain.
" Last Change:  2007-07-04
"
" Options:
"
"   None
"
"
" Related Options:
"   textwidth
"   formatoptions
"   formatlistpat
"   joinspaces
"   cpoptions ('j' flag)
"   comments
"   expandtab
"   tabstop
"   ambiwidth
"
"
" Note:
"   This script is very slow.  Only one or two paragraph (and also Insert mode
"   formatting) can be formatted in practical.
"
"   Do not work when 'formatoptions' have 'a' flag.
"
"   To return 1 means to use Vim's internal formatting but it doesn't work in
"   Normal mode, return value is simply ignored.
"
"   v:lnum can be changed when using "normal! i\<BS>" or something that uses
"   v:lnum.  Take care to use such command in formatexpr.
"
"   v:char is never be space or tab.  When completion is used, v:char is
"   empty.
"
"   Make text reformattable.  Do not insert or remove spaces when it
"   considered unexpected.
"
"
" TODO:
"   'formatoptions': 'q' 'w' 'v' 'b'
"
"   hoge(); /* format comment here */
"   hoge(); /* format
"            * comment
"            * here
"            */
"
"   /* comment */ do_not() + format() + here();
"
"   How to recognize if text is list formatted?
"     1 We have
"     2 20 files.
"   Line 2 is not list but it matches 'formatlistpat'.
"
"   Justify with padding or removing spaces.  How to re-format without
"   breaking user typed space.
"
"
" Reference:
"   UAX #14: Line Breaking Properties
"   http://unicode.org/reports/tr14/
"
"   UAX #11: East Asian Width
"   http://unicode.org/reports/tr11/
"
"   Ward wrap - Wikipedia
"   http://en.wikipedia.org/wiki/Word_wrap

let s:cpo_save = &cpo
set cpo&vim

function autofmt#compat#formatexpr()
  return s:lib.formatexpr()
endfunction

function autofmt#compat#import()
  return s:lib
endfunction

function autofmt#compat#test()
  call s:lib.test()
endfunction

let s:lib = {}
let s:lib.uni = unicode#import()

function s:lib.formatexpr()
  if mode() =~# '[iR]' && &formatoptions =~# 'a'
    " When 'formatoptions' have "a" flag (paragraph formatting), it is
    " impossible to format using User Function.  Paragraph is concatenated to
    " one line before this function is invoked and cursor is placed at end of
    " line.
    return 1
  elseif mode() !~# '[niR]' || (mode() =~# '[iR]' && v:count != 1) || v:char =~# '\s'
    echohl ErrorMsg
    echomsg "Assert(formatexpr): Unknown State: " mode() v:lnum v:count string(v:char)
    echohl None
    return 1
  endif
  if mode() == "n"
    call self.format_normal_mode(v:lnum, v:count)
  else
    call self.format_insert_mode(v:char)
  endif
  return 0
endfunction

function s:lib.format_normal_mode(lnum, count)
  if &textwidth == 0
    return
  endif
  let para = self.get_paragraph(getline(a:lnum, a:lnum + a:count - 1))
  for [i, lines] in reverse(para)
    let lnum = a:lnum + i
    let fo_2 = self.get_second_line_leader(lines)
    let new_lines = self.format_line(self.join_lines(lines), fo_2)
    if len(lines) > len(new_lines)
      silent execute printf("%ddelete _ %d", lnum, len(lines) - len(new_lines))
    elseif len(lines) < len(new_lines)
      call append(lnum, repeat([""], len(new_lines) - len(lines)))
    endif
    call setline(lnum, new_lines)
  endfor
endfunction

function s:lib.format_insert_mode(char)
  " @warning char can be "" when completion is used
  " @return a:char for debug

  let lnum = line('.')
  let col = col('.') - 1
  let vcol = (virtcol('.') - 1) + self.char_width(a:char)
  let line = getline(lnum)

  if &textwidth == 0 || vcol <= &textwidth
        \ || &formatoptions !~# '[tc]'
        \ || (&fo =~# 't' && &fo !~# 'c' && self.parse_leader(line)[1] != "")
        \ || (&fo !~# 't' && &fo =~# 'c' && self.parse_leader(line)[1] == "")
    return a:char
  endif

  " split line at the cursor and add v:char temporary
  let [line, rest] = [line[: col - 1] . a:char, line[col :]]

  let fo_2 = self.get_second_line_leader(getline(lnum, lnum + 1))
  let lines = self.format_line(line, fo_2)
  if len(lines) == 1
    return a:char
  endif

  let col = len(lines[-1]) - len(a:char)

  " remove v:char and restore actual line
  if a:char != ""
    let lines[-1] = substitute(lines[-1], '.$', '', '')
  endif
  let lines[-1] .= rest

  call append(lnum, repeat([""], len(lines) - 1))
  call setline(lnum, lines)
  call cursor(lnum + len(lines) - 1, col + 1)
  return a:char
endfunction

function s:lib.format_line(line, ...)
  let fo_2 = get(a:000, 0, -1)
  let col = self.find_boundary(a:line)
  if col == -1
    return [a:line]
  endif
  let line1 = substitute(a:line[: col - 1], '\s*$', '', '')
  let line2 = substitute(a:line[col :], '^\s*', '', '')
  if fo_2 != -1
    let leader = fo_2
  else
    let leader = self.make_next_line_leader(line1)
  endif
  let line2 = leader . line2
  " TODO: This is ugly hack but simple.  make option?
  " " * */" -> " */"
  if mode() == 'n' && leader =~ '\S' && line2 =~ '^\s*\*\s\+\*/\s*$'
    let line2 = matchstr(line2, '^\s*') . '*/'
  endif
  " use same leader for following lines
  return [line1] + self.format_line(line2, leader)
endfunction

function s:lib.find_boundary(line)
  let start_col = self.skip_leader(a:line)
  if start_col == len(a:line)
    return -1
  endif
  let lst = self.line2list(a:line)
  let break_idx = -1
  let i = 0
  while lst[i].col < start_col
    let i += 1
  endwhile
  let start_idx = i
  let i = self.skip_word(lst, i)
  let i = self.skip_space(lst, i)
  while i < len(lst)
    let brk = self.check_boundary(lst, i)
    let next = self.skip_word(lst, i)
    if brk == "allow_break" && &fo =~ '1'
      " don't break a line after a one-letter word.
      let j = (break_idx == -1) ? start_idx : break_idx
      if (j == 0 || lst[j - 1].c =~ '\s') && lst[j + 1].c =~ '\s'
        let brk = "allow_break_before"
      endif
    endif
    if brk == "allow_break"
      let break_idx = i
      if &textwidth < lst[next - 1].virtcol
        return lst[break_idx].col
      endif
    elseif brk == "allow_break_before"
      if &textwidth < lst[next - 1].virtcol && break_idx != -1
        return lst[break_idx].col
      endif
    endif
    let i = self.skip_space(lst, next)
  endwhile
  return -1
endfunction

function s:lib.check_boundary(lst, i)
  " Check whether a line can be broken before lst[i].
  "
  " @param  lst   line as List of Dictionary
  "   lst[i].c        character
  "   lst[i].w        width of character
  "   lst[i].col      same as col(), but 0 based
  "   lst[i].virtcol  same as virtcol(), but 0 based
  " @param  i     index of lst
  " @return       line break status
  "   "allow_break"         Line can be broken between lst[i-1] and lst[i].
  "   "allow_break_before"  If lst[i] is over the 'textwidth', break a line at
  "                         previous breakable point, if possible.
  "   other                 Do not break.
  "

  let [lst, i] = [a:lst, a:i]

  if lst[i-1].c =~ '\s'
    return "allow_break"
  elseif &fo =~ 'm'
    let bc = char2nr(lst[i-1].c)
    let ac = char2nr(lst[i].c)
    if bc > 255 && ac > 255
      return "allow_break"
    elseif bc > 255 && ac <= 255
      return "allow_break"
    elseif bc <= 255 && ac > 255
      if len(lst) == i + 1 || lst[i+1].c =~ '\s'
        " bug?
        return "no_break"
      endif
      return "allow_break"
    endif
  endif
  return "allow_break_before"
endfunction

function s:lib.skip_word(lst, i)
  " @return end_of_word + 1

  let [lst, i] = [a:lst, a:i + 1]
  if lst[i - 1].c =~ '\h'
    while i < len(lst) && lst[i].c =~ '\w'
      let i += 1
    endwhile
  endif
  return i
endfunction

function s:lib.skip_space(lst, i)
  let [lst, i] = [a:lst, a:i]
  while i < len(lst) && lst[i].c =~ '\s'
    let i += 1
  endwhile
  return i
endfunction

function s:lib.skip_leader(line)
  let col = 0
  if &formatoptions =~# 'c'
    let [indent, com_str, mindent, text, com_flags] = self.parse_leader(a:line)
    let col += len(indent) + len(com_str) + len(mindent)
  else
    let [indent, text] = matchlist(a:line, '\v^(\s*)(.*)$')[1:2]
    let col += len(indent)
  endif
  if &formatoptions =~# 'n'
    let listpat = matchstr(text, &formatlistpat)
    if listpat != ""
      let col += len(listpat)
      let col += len(matchstr(text, '\s*', len(listpat)))
    endif
  endif
  return col
endfunction

function s:lib.get_paragraph(lines)
  " @param  lines   List of String
  " @return         List of Paragraph
  "   [ [start_index, [line1 ,line2, ...]], ...]
  "   For example:
  "     lines = ["", "line2", "line3", "", "", "line6", ""]
  "     => [ [1, ["line2", "line3"]], [5, ["line6"]] ]

  let res = []
  let pl = map(copy(a:lines), 'self.parse_leader(v:val)')
  let i = 0
  while i < len(a:lines)
    while i < len(a:lines) && pl[i][3] == ""
      let i += 1
    endwhile
    if i == len(a:lines)
      break
    endif
    let start = i
    let i += 1
    while i < len(a:lines) && pl[i][3] != ""
      " TODO: check for 'f' comment or 'formatlistpat'.  make option?
      "     orig           vim                 useful?
      "   1: - line1     1: - line1 line2    1: - line1
      "   2: line2                           2: line2
      " use indent?
      "   1: hoge fuga   1: hoge fuga        1: hoge fuga
      "   2:   - list1   2:   - list1        2:   - list1
      "   3:   - list2   3:   - list2 hoge   3:   - list2
      "   4: hoge fuga   4:     fuga         4: hoge fuga
      if pl[start][4] !~# 'f'
            \ && ((pl[i-1][1] == "" && pl[i][1] != "")
            \  || (pl[i-1][1] != "" && pl[i][1] == ""))
        " start/end of comment
        break
      elseif pl[start][4] !~# 'f'
            \ && pl[i-1][1] != pl[i][1] && pl[i][4] !~# '[me]'
        " start of comment (comment leader is changed)
        break
      elseif (&formatoptions =~# 'n' && pl[i][3] =~ &formatlistpat)
        " start of list
        break
      elseif &formatoptions =~# '2'
        " separate with indent
        " make this behavior optional?
        let indent1 = self.str_width(pl[i-1][0] . pl[i-1][1] . pl[i-1][2])
        let indent2 = self.str_width(pl[i][0] . pl[i][1] . pl[i][2])
        if indent1 < indent2
          break
        endif
      endif
      let i += 1
    endwhile
    call add(res, [start, a:lines[start : i - 1]])
  endwhile
  return res
endfunction

function s:lib.join_lines(lines)
  " :join + remove comment leader

  let res = a:lines[0]
  for line in a:lines[1:]
    let [indent, com_str, mindent, text, com_flags] = self.parse_leader(line)
    if com_flags =~# '[se]'
      let text = com_str . mindent . text
    endif
    if res == ""
      let res = text
    elseif text != ""
      let res = self.join_line(substitute(res, '\s\+$', '', ''), text)
    endif
  endfor
  " To remove trailing space?  Vim doesn't do it.
  " let res = substitute(res, '\s\+$', '', '')
  return res
endfunction

function s:lib.join_line(line1, line2)
  " Join two lines.
  "
  " Spaces at end of line1 and comment leader of line2 should be removed
  " before invoking.
  "
  " Make sure that broken line should be joined as original line, so that we
  " can re-format a paragraph without losing user typed space or adding
  " unexpected space.

  let bc = matchstr(a:line1, '.$')
  let ac = matchstr(a:line2, '^.')

  if a:line2 == ""
    return a:line1
  elseif &joinspaces && bc =~# ((&cpoptions =~# 'j') ? '[.]' : '[.?!]')
    return a:line1 . "  " . a:line2
  elseif (&formatoptions =~# 'M' && (len(bc) != 1 || len(ac) != 1))
        \ || (&formatoptions =~# 'B' && (len(bc) != 1 && len(ac) != 1))
    return a:line1 . a:line2
  else
    return a:line1 . " " . a:line2
  endif
endfunction

function s:lib.parse_leader(line)
  "  +-------- indent
  "  | +------ com_str
  "  | | +---- mindent
  "  | | |   + text
  "  v v v   v
  " |  /*    xxx|
  "
  " @return [indent, com_str, mindent, text, com_flags]

  if a:line =~# '^\s*$'
    return [a:line, "", "", "", ""]
  endif
  for [flags, str] in self.parse_opt_comments(&comments)
    let mx = printf('\v^(\s*)(\V%s\v)(\s%s|$)(.*)$', escape(str, '\'),
          \ (flags =~# 'b') ? '+' : '*')
    if a:line =~# mx
      let res = matchlist(a:line, mx)[1:4] + [flags]
      if flags =~# 'n'
        " nested comment
        while 1
          let [indent, com_str, mindent, text, com_flags] = self.parse_leader(res[3])
          if com_flags !~# 'n'
            break
          endif
          let res = [res[0], res[1] . res[2] . com_str, mindent, text, res[4]]
        endwhile
      endif
      return res
    endif
  endfor
  return matchlist(a:line, '\v^(\s*)()()(.*)$')[1:4] + [""]
endfunction

function s:lib.parse_opt_comments(comments)
  " @param  comments  'comments' option
  " @return           [[flags, str], ...]

  let res = []
  for com in split(a:comments, '[^\\]\zs,')
    let [flags; _] = split(com, ':', 1)
    " str can contain ':' and ','
    let str = join(_, ':')
    let str = substitute(str, '\\,', ',', 'g')
    call add(res, [flags, str])
  endfor
  return res
endfunction

function s:lib.line2list(line)
  let res = []
  let [col, virtcol] = [0, 0]
  for c in split(a:line, '\zs')
    let w = self.char_width(c, virtcol)
    let virtcol += w
    call add(res, {
          \ "c": c,
          \ "w": w,
          \ "col": col,
          \ "virtcol": virtcol,
          \ })
    let col += len(c)
  endfor
  return res
endfunction

function s:lib.list2line(lst)
  return join(map(copy(a:lst), 'v:val.c'), '')
endfunction

function s:lib.get_second_line_leader(lines)
  if &formatoptions !~# '2' || len(a:lines) <= 1
    return -1
  endif
  let [indent1, com_str1, mindent1, text1, _] = self.parse_leader(a:lines[0])
  let [indent2, com_str2, mindent2, text2, _] = self.parse_leader(a:lines[1])
  if com_str1 == "" && com_str2 == "" && text2 != ""
    if self.str_width(indent1) > self.str_width(indent2)
      return indent2
    endif
  elseif com_str1 != "" && com_str2 != "" && text2 != ""
    if self.str_width(indent1 . com_str1 . mindent1) > self.str_width(indent2 . com_str2 . mindent2)
      return indent2 . com_str2 . mindent2
    endif
  endif
  return -1
endfunction

function s:lib.make_next_line_leader(line)
  let [indent, com_str, mindent, text, com_flags] = self.parse_leader(a:line)
  if &formatoptions =~# 'n'
    let listpat = matchstr(text, &formatlistpat)
    let listpat_indent = repeat(' ', self.str_width(listpat))
  else
    let listpat_indent = ""
  endif
  if &formatoptions !~# 'c'
    if com_str == ""
      return indent . listpat_indent
    else
      return indent
    endif
  elseif com_str == ""
    return indent . listpat_indent
  elseif com_flags =~# 'f'
    return indent . repeat(' ', self.str_width(com_str)) . mindent . listpat_indent
  elseif com_flags =~# 's'
    " make a middle of three-piece comment
    " TODO: keep <Tab> in mindent
    let coms = self.parse_opt_comments(&comments)
    for i in range(len(coms))
      if coms[i][0] =~# 's'
        let [s, m, e] = coms[i : i + 2]
        if s == [com_flags, com_str]
          break
        endif
      endif
    endfor
    let off = matchstr(com_flags, '-\?\d\+\ze[^0-9]*') + 0
    let adjust = matchstr(com_flags, '[lr]\ze[^lr]*')
    if adjust == 'r'
      let newindent = max([0, self.str_width(indent . com_str) - self.str_width(m[1])])
      let pad = 0
    else
      let newindent = max([0, self.str_width(indent)])
      let pad = max([0, self.str_width(com_str) - self.str_width(m[1])])
    endif
    if newindent + off > 0
      let newindent += off
    endif
    if mindent == ""
      let pad = 1
    else
      let pad = max([0, pad + self.str_width(mindent) - max([0, off])])
    endif
    if &expandtab
      let leader = repeat(' ', newindent) . m[1] . repeat(' ', pad)
    else
      let leader = repeat("\t", newindent / &tabstop) .
            \ repeat(' ', newindent % &tabstop) . m[1] . repeat(' ', pad)
    endif
    return leader . listpat_indent
  elseif com_flags =~# 'm'
    return indent . com_str . mindent . listpat_indent
  elseif com_flags =~# 'e'
    return indent
  else
    return indent . com_str . mindent . listpat_indent
  endif
endfunction

function s:lib.str_width(str, ...)
  let vcol = get(a:000, 0, 0)
  let n = 0
  for c in split(a:str, '\zs')
    let n += self.char_width(c, n + vcol)
  endfor
  return n
endfunction

function s:lib.char_width(c, ...)
  let vcol = get(a:000, 0, 0)
  if a:c == ""
    return 0
  elseif a:c == "\t"
    return self.tab_width(vcol)
  elseif len(a:c) == 1  " quick check
    return 1
  else
    let w = self.uni.prop_east_asian_width(a:c)
    if w == "A"
      return (&ambiwidth == "double") ? 2 : 1
    elseif w =~ '[WF]'
      return 2
    else
      return 1
    endif
  endif
endfunction

function s:lib.tab_width(vcol)
  return &tabstop - (a:vcol % &tabstop)
endfunction

function s:lib.get_opt(name)
  return  get(w:, a:name,
        \ get(t:, a:name,
        \ get(b:, a:name,
        \ get(g:, a:name,
        \ get(self, a:name)))))
endfunction

function s:lib.do_test(testname, input, result)
  echo a:testname
  if type(a:input) == type([]) || a:input == strtrans(a:input)
    %delete
    call setline(1, a:input)
    normal! ggVGgq
    if getline(1, "$") != a:result
      throw a:testname . " normal failed!"
    endif
  endif
  if type(a:input) == type("")
    %delete
    execute "normal! i" . a:input
    if getline(1, "$") != a:result
      throw a:testname . " insert failed!"
    endif
  endif
endfunction

function s:lib.test()
  new

  let b:autofmt = self
  setl formatexpr=b:autofmt.formatexpr()
  set debug=msg
  setl textwidth=10 formatoptions=tcnr formatlistpat& comments&
  setl tabstop& shiftwidth& softtabstop& expandtab&

  let start = reltime()

  call self.do_test("test1",
        \ "aaaaa",
        \ ["aaaaa"])
  call self.do_test("test2",
        \ "aaaaa bbbb",
        \ ["aaaaa bbbb"])
  call self.do_test("test3",
        \ "aaaaa bbbbb",
        \ ["aaaaa", "bbbbb"])
  call self.do_test("test4",
        \ "aaaaa    bbbbb     ",
        \ ["aaaaa", "bbbbb     "])
  call self.do_test("test5",
        \ "aaaaa bbbbb ccccc",
        \ ["aaaaa", "bbbbb", "ccccc"])
  call self.do_test("test6",
        \ "aaaaaaaaaabbbbbbbbbb",
        \ ["aaaaaaaaaabbbbbbbbbb"])
  call self.do_test("test7",
        \ "  aaaaaaaaaabbbbbbbbbb",
        \ ["  aaaaaaaaaabbbbbbbbbb"])
  call self.do_test("test8",
        \ ["aaaa", "bbbb", "cccccccccccc", "dddd"],
        \ ["aaaa bbbb", "cccccccccccc", "dddd"])
  call self.do_test("test9",
        \ "/* aaaaa bbbbb ccccc",
        \ ["/* aaaaa", " * bbbbb", " * ccccc"])
  call self.do_test("test10",
        \ ["/* aaaaa bbbbb ccccc */"],
        \ ["/* aaaaa", " * bbbbb", " * ccccc", " */"])
  call self.do_test("test11",
        \ ["/* aaa", " * bbb", " * ccc", " * ddd", " */"],
        \ ["/* aaa bbb", " * ccc ddd", " */"])
  call self.do_test("test12",
        \ "1. aaaaa bbbbb",
        \ ["1. aaaaa", "   bbbbb"])
  call self.do_test("test13",
        \ "/*\<CR>1. aaaaa bbbbb",
        \ ["/*", " * 1. aaaaa", " *    bbbbb"])
  call self.do_test("test14",
        \ "\t/*   aaa bbb",
        \ ["\t/*   aaa", "\t *   bbb"])
  call self.do_test("test15",
        \ ["", "", "aaa", "aaa", "", "/*", " * bbb", " * bbb", " *", " * ccc", " */", ""],
        \ ["", "", "aaa aaa", "", "/*", " * bbb bbb", " *", " * ccc", " */", ""])

  setl fo+=2
  let &l:comments = 'sO:* -,mO:*  ,exO:*/,s1:/*,mb:*,ex:*/,://'
  " check for 'mO:*  '

  call self.do_test("test16",
        \ ["  aaaaa bbbbb", "ccccc ddddd"],
        \ ["  aaaaa", "bbbbb", "ccccc", "ddddd"])
  call self.do_test("test17",
        \ ["/*  aaaaa bbbbb", " * ccccc ddddd", " *", " *  aaaaa bbbbb", " * ccccc ddddd", " */"],
        \ ["/*  aaaaa", " * bbbbb", " * ccccc", " * ddddd", " *", " *  aaaaa", " * bbbbb", " * ccccc", " * ddddd", " */"])

  echo reltimestr(reltime(start))
endfunction

let &cpo = s:cpo_save

