#NoEnv
#NoTrayIcon
SetBatchLines -1

#Include <logging>
#Include <optparser>
#Include <system>
#Include <ansi>
#Include <string>
#Include <arrays>
#Include *i %A_ScriptDir%\.versioninfo

Main:
	_main := new Logger("app.xxd.Main")

	; Define Command Parser Options as Super global vars to make them everywhere accessable
	global G_autoskip := false
		 , G_bits := false
		 , G_cols := ""
		 , G_groupsize := ""
		 , G_length := 0
		 , G_plain := false
		 , G_revert := false
		 , G_seek := 0
		 , G_start_at := 0
		 , G_uppercase := false
		 , G_help := false
		 , G_version := false

	op := new OptParser(["xxd [options] [--] [<infile> [<outfile>]]"
					   , "xxd -r [-s <[-]offset>] [-c <cols>] [-p] [--] [<infile> [<outfile>]]"]
					   , OptParser.PARSER_ALLOW_DASHED_ARGS)
	op.Add(new OptParser.Boolean("a", "autoskip", G_autoskip, "toogle autoskip: A single '*' replaces nul-lines. Default off"))
	op.Add(new Optparser.Boolean("b", "bits", G_bits, "binary digit dump (incompatible with -p,-i,-r). Default hex"))
	op.Add(new OptParser.String("c", "cols", G_cols, "cols", "format <cols> octets per line. Default 16 (-p: 30)",, G_cols))
	op.Add(new OptParser.String("g", "groupsize", G_groupsize, "bytes", "number of octets per group in normal output. Default 2",, G_groupsize))
	op.Add(new OptParser.Boolean("i", "include", G_include, "output in AHK include file style"))
	op.Add(new OptParser.String("l", "len", G_length, "len", "stop after <len> octets"))
	op.Add(new OptParser.Boolean("p", "plain", G_plain, "output in postscript plain hexdump style"))
	op.Add(new OptParser.Boolean("r", "revert", G_revert, "reverse operation: convert (or patch) hexdump into binary"))
	op.Add(new OptParser.String("s", "seek", G_seek, "[+][-]seek", "start at <seek> bytes abs. (or +: rel.) infile offset"))
	op.Add(new OptParser.Boolean("u", "", G_uppercase, "use uppercase hex letters"))
	op.Add(new OptParser.Boolean("h", "help", G_help, "", OptParser.OPT_HIDDEN))
	op.Add(new OptParser.Boolean("v", "version", G_version, "", OptParser.OPT_HIDDEN))

	try {
		RC := 1 ; No errors encountered

		files := op.Parse(System.vArgs)
		infile := Arrays.Shift(files)
		outfile := Arrays.Shift(files)
		if (files.MaxIndex() <> "")
			throw Exception("",, 2)

		; Resize all String params
		op.TrimArg(G_cols)
		op.TrimArg(G_groupsize)
		op.TrimArg(G_length)
		op.TrimArg(G_seek)

		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_autoskip", G_autoskip)
			_main.Finest("G_bits", G_bits)
			_main.Finest("G_cols", G_cols)
			_main.Finest("G_groupsize", G_groupsize)
			_main.Finest("G_length", G_length)
			_main.Finest("G_plain", G_plain)
			_main.Finest("G_revert", G_revert)
			_main.Finest("G_seek", G_seek)
			_main.Finest("G_start_at", G_start_at)
			_main.Finest("G_uppercase", G_uppercase)
			_main.Finest("G_help", G_help)
			_main.Finest("G_version", G_version)
			_main.Finest("infile", infile)
			_main.Finest("outfile", outfile)
		}

		if (G_help) {
			Ansi.WriteLine(op.Usage())
			exitapp _main.Exit()
		}

		if (G_version) {
			Ansi.WriteLine(G_VERSION_INFO.NAME "/" G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
			exitapp _main.Exit()
		}

		; Plausibility checks
		if (files.MaxIndex() > 2)
			throw Exception("",, 1)

		if (G_bits && (G_plain || G_revert)) {
			G_bits := false
			if (_main.Logs(Logger.Warning))
				_main.Warning("-b is incompatible with -p (" G_plain ") or -r (" G_revert "); -b is ignored")
		}

		if (G_revert && (G_autoskip || G_include || G_bits || G_groupsize || G_length))
			throw Exception("",, -1)

		; Handle defaults
		if (G_plain && G_cols = "") {
			G_cols := 30
			if (_main.Logs(Logger.Info))
				_main.Info("-p: Setting 'cols' to 30")
		} else if (G_bits) {
			if (G_cols = "") {
				G_cols := 6
				if (_main.Logs(Logger.Info))
					_main.Info("-b: Setting 'cols' to 6")
			}
			if (G_groupsize = "") {
				G_groupsize := 1
				if (_main.Logs(Logger.Info))
					_main.Info("-b: Setting 'groupsize' to 1")
			}
		} else if (G_include) {
			if (G_cols = "") {
				G_cols := 12
				if (_main.Logs(Logger.Info))
					_main.Info("-i: Setting 'cols' to 12")
			}
		} else {
			if (G_cols = "") {
				G_cols := 16
				if (_main.Logs(Logger.Info))
					_main.Info("Setting 'cols' to default " G_cols)
			}
			if (G_groupsize = "") {
				G_groupsize := 2
				if (_main.Logs(Logger.Info)) {
					_main.Info("Setting 'groupsize' to default " G_groupsize)
				}
			}
		}

		if (G_revert)
			if (G_plain)
				generate_binary_plain(infile, outfile)
			else
				generate_binary(infile, outfile)
		else if (G_include)
			generate_include(infile, outfile)
		else
			generate_dump(infile, outfile)

	} catch _ex {
		if (_ex.Message <> "")
			Ansi.WriteLine(_ex.Message)
		Ansi.WriteLine(op.Usage())

		RC := _ex.Extra
	}

	OutputDebug Done.
exitapp _main.Exit(RC)

generate_dump(infile, outfile) {
	_log := new Logger("app.xxd." A_ThisFunc)

	if (_log.Logs(Logger.Input)) {
		_log.Input("infile", infile)
		_log.Input("outfile", outfile)
	}

	cur_code_sum := 0 ; Sum of all bytes in current line
	nul_line_count := 0 ; Number of consecutive nul lines
	cur_octets_count := 0 ; Number of octets in current line
	total_octets_count := 0 ; Number of printed octets

	try {
		_in := open_infile(infile)
		_out := open_outfile(outfile)

		_offset := seek(_in)
		out_line := offset(_offset)
		out_line_right := ""

		while (!_in.AtEOF) {
			if (G_length && total_octets_count >= G_length)
				break
			byte := _in.ReadUChar()
			cur_code_sum += byte
			out_line .= octet(byte)
			cur_octets_count++
			total_octets_count++
			if (!G_plain && !G_include) { ; Fill right hand size with readable chars
				if (byte >= 32 && byte < 127)
					out_line_right .= Chr(byte)
				else
					out_line_right .= "."
				if (!Mod(cur_octets_count, G_groupsize) && cur_octets_count < G_cols && G_groupsize <> 0) { ; Grouping 
					out_line .= " "
				}
			}
			if (!Mod(cur_octets_count, G_cols)) { ; Max no of cols reached
				if (G_autoskip && !G_include)
					if (cur_code_sum = 0)
						nul_line_count++
					else
						nul_line_count := 0
				if (nul_line_count <= 1) ; Print a "normal" line or the first "nul" line
					_out.WriteLine(out_line "  " out_line_right)
				else if (nul_line_count = 2) ; Print a single "*" for a second or more consecutive "nul" lines; print nothing for more consecutive "nul" lines
					_out.WriteLine("*")
				_offset := _offset + G_cols
				out_line := offset(_offset)
				out_line_right := ""
				cur_code_sum := 0
				cur_octets_count := 0
			}
		}
		if (cur_octets_count > 0) { ; Fill last line if neccessary
			cur_octets_count++
			while (cur_octets_count <= G_cols) {
				out_line .= (G_bits ? "        " : "  ")
				if (!G_plain && G_groupsize <> 0 && cur_octets_count < G_cols && !Mod(cur_octets_count, G_groupsize))
					out_line .= " "
				cur_octets_count++
			}
			_out.WriteLine(out_line "  " out_line_right)
		}
	} finally {
		if (_in)
			_in.Close()
		if (_out)
			_out.Close()
	}

	return _log.Exit()
}

generate_include(infile, outfile) {
	_log := new Logger("app.xxd." A_ThisFunc)

	if (_log.Logs(Logger.Input)) {
		_log.Input("infile", infile)
		_log.Input("outfile", outfile)
	}

	nul_line_count := 0 ; Number of consecutive nul lines
	cur_octets_count := 0 ; Number of octets in current line
	total_octets_count := 0 ; Number of printed octets
	continuation_limit := 0 ; Handle limit of max. expression length (251 token)

	try {
		_in := open_infile(infile)
		_out := open_outfile(outfile)

		_offset := seek(_in)
		varname := filename2var(infile)
		_out.WriteLine(varname " := []")
		indent := " ".Repeat(StrLen(varname) + 7)
		out_line := ""

		while (!_in.AtEOF) {
			if (G_length && total_octets_count >= G_length)
				break
			byte := _in.ReadUChar()
			cur_octets_count++
			total_octets_count++
			out_line .= (continuation_limit = 0 ? varname ".Insert( 0x" offset(total_octets_count, "") "`n" indent ", " : out_line = "" ? indent ", " : ", ") "0x" octet(byte)
			if (continuation_limit > 250) {
				_out.WriteLine(out_line " )")
				out_line := ""
				continuation_limit := 0
				cur_octets_count := 0
			} else
				continuation_limit++
			if (!Mod(cur_octets_count, G_cols)) { ; Max no of cols reached
				if (G_length && total_octets_count >= G_Length)
					out_line .= " )"
				_out.WriteLine(out_line)
				out_line := ""
				_offset := _offset + G_cols
				cur_octets_count := 0
			}
		}
		if (cur_octets_count > 0) { ; Fill last line if neccessary
			_out.WriteLine(out_line " )")
		}
		_out.WriteLine(varname "_len := " total_octets_count)
	} finally {
		if (_in)
			_in.Close()
		if (_out)
			_out.Close()
	}

	return _log.Exit()
}

/*
 * Function: generate_binary
 *     Convert hex dump into binary.
 */
generate_binary(infile, outfile) {
	_log := new Logger("app.xxd." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("infile", infile)
		_log.Input("outfile", outfile)
	}

	line_expr := "iO)^([0-9a-z]+): "
	loop % (G_cols // G_groupsize) {
		loop % G_groupsize
			line_expr .= "([0-9a-z]{2}|\s*)"
		line_expr .= " ?"
	}
	line_expr .= "\s*.*?$\s*"

	try {
		_in := open_infile(infile)
		_out := open_outfile(outfile, "rw")

		offset := _in.Position
		while (!_in.AtEOF()) {
			if (G_length && offset >= G_length)
				break
			line := _in.ReadLine()
			if (RegExMatch(line, line_expr, $)) {
				file_offset := "0x" $[1]
				if (file_offset > offset) {
					if (file_offset <= _out.Length) {
						_out.Seek(file_offset)
						offset := file_offset
					} else while (offset < file_offset) {
						if (offset >= G_seek)
							_out.WriteUChar(0x00)
						offset++
					}
				}
				loop %G_cols% {
					if (Trim($[A_Index+1], "`n`r") = "")
						break
					if (offset >= G_seek) {
						_out.WriteUChar(b := "0x" $[A_Index+1])
					}
					offset++
				}
			} else
				if (_log.Logs(Logger.Warning))
					_log.Warning("Invalid line: #" A_Index ": " line)
		}
	} finally {
		if (_in)
			_in.Close()
		if (_out) {
			_out.Close()
		}
	}

	return _log.Exit()	
}

/*
 * Function: generate_binary_plain
 *     Convert plain hex data into binary
 */
generate_binary_plain(infile, outfile) {
	_log := new Logger("app.xxd." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("infile", infile)
		_log.Input("outfile", outfile)
	}

	line_expr := "i)^([0-9a-f]{2})*"

	try {
		_in := open_infile(infile)
		_out := open_outfile(outfile, "rw")

		offset := 0
		while (!_in.AtEOF()) {
			if (G_length && offset >= G_length)
				break
			line := _in.ReadLine()
			if (RegExMatch(line, line_expr, $)) {
				i := 1
				while (i < StrLen($)) {
					if (offset >= G_seek)
						_out.WriteUChar(b := "0x" SubStr($, i, 2))
					offset++
					i+=2
				}
			} else
				if (_log.Logs(Logger.Warning))
					_log.Warning("Invalid line: #" A_Index ": " line)
		}
	} finally {
		if (_in)
			_in.Close()
		if (_out) {
			_out.Close()
		}
	}
	
	return _log.Exit()
}

open_infile(infile) {
	_log := new Logger("app.xxd." A_ThisFunc)

	if (_log.Logs(Logger.Input))
		_log.Input("infile", infile)

	try
		if (infile = "" || infile = "-")
			i := Ansi.StdIn
		else
			i := FileOpen(infile, "r")
	catch _ex 
		throw _log.Exit(Exception("xxd: Failed to open file: " infile,, 3))

	return _log.Exit(i)
}

open_outfile(outfile, mode = "w") {
	_log := new Logger("app.xxd." A_ThisFunc)

	if (_log.Logs(Logger.Input)) {
		_log.Input("outfile", outfile)
		_log.Input("mode", mode)
	}

	try
		if (outfile = "" || outfile = "-")
			o := Ansi.StdOut
		else
			o := FileOpen(outfile, mode)
	catch _ex
		throw _log.Exit(Exception("xxd: Failed to open file: " outfile,, 4))

	return _log.Exit(o)
}

/*
 * Function: octet
 *     Return displayable octet
 */
octet(value) {
	static DIGIT_TAB := {  0: ["0", "0", "0000"]
						,  1: ["1", "1", "0001"]
						,  2: ["2", "2", "0010"]
						,  3: ["3", "3", "0011"]
						,  4: ["4", "4", "0100"]
						,  5: ["5", "5", "0101"]
						,  6: ["6", "6", "0110"]
						,  7: ["7", "7", "0111"]
						,  8: ["8", "8", "1000"]
						,  9: ["9", "9", "1001"]
						, 10: ["a", "A", "1010"]
						, 11: ["b", "B", "1011"]
						, 12: ["c", "C", "1100"]
						, 13: ["d", "D", "1101"]
						, 14: ["e", "E", "1110"]
						, 15: ["f", "F", "1111"]}

	i := (G_bits ? 3 : (G_uppercase ? 2 : 1))
	
	d1 := value // 16
	d2 := Mod(value, 16)

	return DIGIT_TAB[d1, i] . DIGIT_TAB[d2, i]
}

offset(value, suffix = ": ") {
	static DIGIT_TAB := {  0: ["0", "0"]
						,  1: ["1", "1"]
						,  2: ["2", "2"]
						,  3: ["3", "3"]
						,  4: ["4", "4"]
						,  5: ["5", "5"]
						,  6: ["6", "6"]
						,  7: ["7", "7"]
						,  8: ["8", "8"]
						,  9: ["9", "9"]
						, 10: ["a", "A"]
						, 11: ["b", "B"]
						, 12: ["c", "C"]
						, 13: ["d", "D"]
						, 14: ["e", "E"]
						, 15: ["f", "F"]}

	if (G_plain)
		return 

	i := (G_uppercase ? 2 : 1)

	n := StrLen(value+0) - 1
	hex := ""

	while (n > 0) {
		f := 16**(n--)
		d := value // f
		value -= d * f
		hex .= DIGIT_TAB[d, i]
	}

	return SubStr("0000000" hex . DIGIT_TAB[Mod(value, 16), i], -6) suffix
}

/*
 * Function: seek
 *     Move file pointer to a given position.
 */
seek(infile) {

	_log := new Logger("app.xxd." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("infile", infile)
	}
	
	if (G_seek) {
		RegExMatch(G_seek, "(?P<plus>\+)?(?P<minus>-)?(?P<number>\d+)", seek_)
		if (_log.Logs(Logger.Finest)) {
			_log.Finest("seek_plus", seek_plus)
			_log.Finest("seek_minus", seek_minus)
			_log.Finest("seek_number", seek_number)
		}
		if (seek_plus && !seek_minus)
			infile.Seek(seek_number, 1)
		else if (!seek_plus && seek_minus)
			infile.Seek(seek_minus seek_number, 2)
		else
			infile.Seek(seek_number)
	} else
		G_seek := 0

	return _log.Exit(infile.Position)
}

/*
 * Function: filename2var
 *     Generate a variable name on base of a filename.
 */
filename2var(filename) {
	_log := new Logger("app.xxd." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("filename", filename)
	}

	SplitPath filename,,, ext, name
	ext := RegExReplace(ext, "i)[^a-z0-9_#$@]", "_")
	name := RegExReplace(name, "i)[^a-z0-9_#$@]", "_")
	
	return _log.Exit(name "_" ext)
}
; vim: ts=4:sts=4:sw=4:tw=0:noet
