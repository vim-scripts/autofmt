" Maintainer:   Yukihiro Nakadaira <yukihiro.nakadaira@gmail.com>
" License:      This file is placed in the public domain.
" Last Change:  2011-01-08
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
"   autoindent
"   copyindent
"
"
" Note:
"   This script is very slow.  Only one or two paragraph (and also Insert mode
"   formatting) can be formatted in practical.
"
"   Do not work when 'formatoptions' have 'a' flag.
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
"   'cindent', 'lispindent', 'smartindent', 'indentexpr'
"
"   'formatoptions': 'a' 'w' 'v' 'b' 'l'
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

if exists('*strdisplaywidth')
  let s:strdisplaywidth = function('strdisplaywidth')
else
  function s:strdisplaywidth(str, ...)
    let vcol = get(a:000, 0, 0)
    let w = 0
    for c in split(a:str, '\zs')
      if c == "\t"
        let w += &tabstop - ((vcol + w) % &tabstop)
      elseif c =~ '^.\%2v'  " single-width char
        let w += 1
      elseif c =~ '^.\%3v'  " double-width char or ctrl-code (^X)
        let w += 2
      elseif c =~ '^.\%5v'  " <XX>    (^X with :set display=uhex)
        let w += 4
      elseif c =~ '^.\%7v'  " <XXXX>  (e.g. U+FEFF)
        let w += 6
      endif
    endfor
    return w
  endfunction
endif

let s:lib = {}

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
  if mode() == 'n'
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
    let lines[0] = self.retab(lines[0])
    let fo_2 = self.get_second_line_leader(lines)
    let new_lines = self.format_lines(lines, fo_2)
    if len(lines) > len(new_lines)
      silent execute printf("%ddelete _ %d", lnum, len(lines) - len(new_lines))
    elseif len(lines) < len(new_lines)
      call append(lnum, repeat([""], len(new_lines) - len(lines)))
    endif
    call setline(lnum, new_lines)
    call cursor(lnum + len(new_lines) - 1, 1)
  endfor
endfunction

function s:lib.format_insert_mode(char)
  " @warning char can be "" when completion is used
  " @return a:char for debug

  let lnum = line('.')
  let col = col('.') - 1
  let vcol = (virtcol('.') - 1) + s:strdisplaywidth(a:char)
  let line = getline(lnum)

  if &textwidth == 0 || vcol <= &textwidth
        \ || &formatoptions !~# '[tc]'
        \ || (&fo !~# 't' && &fo =~# 'c' && self.parse_leader(line)[1] == "")
    return a:char
  endif

  " split line at the cursor and add v:char temporary
  let [line, rest] = [line[: col - 1] . a:char, line[col :]]

  let fo_2 = self.get_second_line_leader(getline(lnum, lnum + 1))
  let lines = self.format_lines([line], fo_2)
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

function s:lib.format_lines(lines, fo_2)
  let res = []
  let line = self.join_lines(a:lines)
  while 1
    let col = self.find_boundary(line)
    if col == -1
      call add(res, line)
      break
    endif
    let line1 = substitute(line[: col - 1], '\s*$', '', '')
    let line2 = substitute(line[col :], '^\s*', '', '')
    if a:fo_2 != -1
      let leader = a:fo_2
    else
      let leader = self.make_next_line_leader(line1)
    endif
    call add(res, line1)
    let line = leader . line2
  endwhile
  if self.is_comment_enabled() && mode() == 'n'
    " " * */" -> " */"
    let [indent, com_str, mindent, text, com_flags] = self.parse_leader(res[-1])
    if com_flags =~# 'm'
      let [s, m, e] = self.find_three_piece_comments(&comments, com_flags, com_str)
      if text == e[1]
        let res[-1] = indent . e[1]
      endif
    endif
  endif
  return res
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
  let is_prev_one_letter = 0
  let start_idx = i
  let i = self.skip_word(lst, i)
  let i = self.skip_space(lst, i)
  while i < len(lst)
    let brk = self.check_boundary(lst, i)
    let next = self.skip_word(lst, i)
    if is_prev_one_letter && brk == "allow_break" && &fo =~ '1'
      " don't break a line after a one-letter word.
      let brk = "allow_break_before"
    endif
    if brk == "allow_break"
      let break_idx = i
      if &textwidth < lst[next - 1].virtcol
        return lst[break_idx].col
      endif
      let is_prev_one_letter = (i == 0 || lst[i - 1].c =~ '\s') &&
            \ (i + 1 == len(lst) || lst[i + 1].c =~ '\s')
    elseif brk == "allow_break_before"
      if &textwidth < lst[next - 1].virtcol && break_idx != -1
        return lst[break_idx].col
      endif
      let is_prev_one_letter = (i == 0 || lst[i - 1].c =~ '\s') &&
            \ (i + 1 == len(lst) || lst[i + 1].c =~ '\s')
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
  elseif &fo =~# 'm'
    let bc = char2nr(lst[i-1].c)
    let ac = char2nr(lst[i].c)
    if bc > 255 || ac > 255
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
  if self.is_comment_enabled()
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
  "
  " @see opt.c:same_leader()
  "
  " TODO: check for 'f' comment or 'formatlistpat'.  make option?
  "     orig           vim                 useful?
  "   1: - line1     1: - line1 line2    1: - line1
  "   2: line2                           2: line2
  " use indent?
  "   1: hoge fuga   1: hoge fuga        1: hoge fuga
  "   2:   - list1   2:   - list1        2:   - list1
  "   3:   - list2   3:   - list2 hoge   3:   - list2
  "   4: hoge fuga   4:     fuga         4: hoge fuga

  let res = []
  let pl = []
  for line in a:lines
    call add(pl, self.parse_leader(line))
  endfor
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
      if pl[start][4] =~# 'f'
        if pl[i][1] != ''
          break
        endif
      elseif pl[start][4] =~# 'e'
        break
      elseif pl[start][4] =~# 's'
        if pl[i][4] !~# 'm'
          break
        endif
      elseif pl[i-1][1] != pl[i][1] || (pl[i-1][2] != '' && pl[i][2] == '')
        " start/end of comment or different comment
        break
      endif
      if (&formatoptions =~# 'n' && pl[i][3] =~ &formatlistpat)
        " start of list
        break
      elseif &formatoptions =~# '2'
        " separate with indent
        " make this behavior optional?
        let indent1 = s:strdisplaywidth(pl[i-1][0] . pl[i-1][1] . pl[i-1][2])
        let indent2 = s:strdisplaywidth(pl[i][0] . pl[i][1] . pl[i][2])
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
    if self.is_comment_enabled()
      let [indent, com_str, mindent, text, com_flags] = self.parse_leader(line)
      if com_flags =~# '[se]'
        let text = com_str . mindent . text
      endif
    else
      let text = line
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

function s:lib.is_comment_enabled()
  if mode() == 'n'
    return &formatoptions =~# 'q'
  else
    return &formatoptions =~# 'c'
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

function s:lib.find_three_piece_comments(comments, flags, str)
  let coms = self.parse_opt_comments(a:comments)
  for i in range(len(coms))
    if coms[i][0] == a:flags && coms[i][1] == a:str
      if a:flags =~# 's'
        return coms[i : i + 2]
      elseif a:flags =~# 'm'
        return coms[i - 1 : i + 1]
      elseif a:flags =~# 'e'
        return coms[i - 2 : i]
      endif
    endif
  endfor
endfunction

function s:lib.line2list(line)
  let res = []
  let [col, virtcol] = [0, 0]
  for c in split(a:line, '\zs')
    let w = s:strdisplaywidth(c, virtcol)
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
    if s:strdisplaywidth(indent1) > s:strdisplaywidth(indent2)
      return indent2
    endif
  elseif com_str1 != "" && com_str2 != "" && text2 != ""
    if s:strdisplaywidth(indent1 . com_str1 . mindent1) > s:strdisplaywidth(indent2 . com_str2 . mindent2)
      return indent2 . com_str2 . mindent2
    endif
  endif
  return -1
endfunction

function s:lib.make_next_line_leader(line)
  let do_si = !&paste && &smartindent && !&cindent
  let [indent, com_str, mindent, text, com_flags] = self.parse_leader(a:line)
  let extra_space = ''
  let leader = indent . com_str . mindent
  if &formatoptions =~# 'n'
    let listpat = matchstr(text, &formatlistpat)
    let listpat_indent = repeat(' ', s:strdisplaywidth(listpat))
  else
    let listpat_indent = ""
  endif
  if !self.is_comment_enabled()
    if com_str == ""
      if !&autoindent && listpat_indent == ''
        let indent = ''
      endif
      let [indent, com_str, mindent] = [indent, '', listpat_indent]
    else
      if !&autoindent
        let indent = ''
      endif
      let [indent, com_str, mindent] = [indent, '', '']
    endif
  elseif com_str == ""
    if !&autoindent
      let indent = ''
    endif
    let [indent, com_str, mindent] = [indent, '', listpat_indent]
  elseif com_flags =~# 'e'
    let [indent, com_str, mindent] = [indent, '', '']
  else
    let extra_space = ''
    if com_flags =~# 's'
      if !&autoindent
        let indent = ''
      endif
      let [s, m, e] = self.find_three_piece_comments(&comments, com_flags, com_str)
      let lead_repl = m[1]
      if leader !~ ' $' && m[0] =~# 'b'
        let extra_space = ' '
      endif
    elseif com_flags =~# 'm'
      " pass
    elseif com_flags =~# 'f'
      let lead_repl = ''
    else
      " pass
    endif
    if exists('lead_repl')
      let off = matchstr(com_flags, '-\?\d\+\ze[^0-9]*') + 0
      let adjust = matchstr(com_flags, '\c[lr]\ze[^lr]*')
      if adjust ==# 'r'
        let newindent = s:strdisplaywidth(indent . com_str) - s:strdisplaywidth(lead_repl)
        if newindent < 0
          let newindent = 0
        endif
      else
        let newindent = s:strdisplaywidth(indent)
        let w1 = s:strdisplaywidth(com_str)
        let w2 = s:strdisplaywidth(lead_repl)
        if w1 > w2 && mindent[0] != "\t"
          let mindent = repeat(' ', w1 - w2) . mindent
        endif
      endif
      let _leader = repeat(' ', newindent) . lead_repl . mindent
      " Recompute the indent, it may have changed.
      if &autoindent || do_si
        let newindent = s:strdisplaywidth(matchstr(_leader, '^\s*'))
      endif
      if newindent + off < 0
        let off = -newindent
        let newindent = 0
      else
        let newindent += off
      endif
      " Correct trailing spaces for the shift, so that alignment remains equal.
      " Don't do it when there is a tab before the space
      while off > 0 && _leader != '' && _leader =~ ' $' && _leader !~ '\t'
        let _leader = strpart(_leader, 0, len(_leader) - 1)
        let off -= 1
      endwhile
      let _ = matchlist(_leader, '^\s*\(\S*\)\(\s*\)$')
      if _[2] != ''
        let extra_space = ''
      endif
      let [indent, com_str, mindent] = [repeat(' ', newindent), _[1], _[2] . extra_space . listpat_indent]
    else
      let [indent, com_str, mindent] = [indent, com_str, mindent . listpat_indent]
    endif
  endif
  if &copyindent
    let [indent, rest] = self.copy_indent(a:line, indent)
  else
    let indent = self.retab(indent)
    let rest = ''
  endif
  let leader = indent . rest . com_str . mindent
  if com_str == ''
    let leader = self.retab(leader, len(indent))
  endif
  return leader
endfunction

function s:lib.copy_indent(line1, line2)
  " @return [copied_indent, rest_indent . text]
  let indent1 = matchstr(a:line1, '^\s*')
  let indent2 = matchstr(a:line2, '^\s*')
  let text = matchstr(a:line2, '^\s*\zs.*$')
  let n1 = s:strdisplaywidth(indent1)
  let n2 = s:strdisplaywidth(indent2)
  let indent = matchstr(indent1, '^\s*\%<' . (n2 + 2) . 'v')
  if n2 > n1
    let text = repeat(' ', n2 - n1) . text
  endif
  return [indent, text]
endfunction

function s:lib.retab(line, ...)
  let col = get(a:000, 0, 0)
  let expandtab = get(a:000, 1, &expandtab)
  let tabstop = get(a:000, 2, &tabstop)
  let s2 = matchstr(a:line, '^\s*', col)
  if s2 == ''
    return a:line
  endif
  let s1 = strpart(a:line, 0, col)
  let t = strpart(a:line, col + len(s2))
  let n1 = s:strdisplaywidth(s1)
  let n2 = s:strdisplaywidth(s2, n1)
  if expandtab
    let s2 = repeat(' ', n2)
  else
    if n1 != 0 && n2 >= (tabstop - (n1 % tabstop))
      let n2 += n1 % tabstop
    endif
    let s2 = repeat("\t", n2 / tabstop) . repeat(' ', n2 % tabstop)
  endif
  return s1 . s2 . t
endfunction

function s:lib.get_opt(name)
  return  get(w:, a:name,
        \ get(t:, a:name,
        \ get(b:, a:name,
        \ get(g:, a:name,
        \ get(self, a:name)))))
endfunction

let &cpo = s:cpo_save

