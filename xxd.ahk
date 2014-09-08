#NoEnv
SetBatchLines -1

#Include <logging>
#Include <optparser>
#Include <system>
#Include <console>
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
	op.Add(new OptParser.String("l", "len", G_length, "len", "stop after <len> octets"))
	op.Add(new OptParser.Boolean("p", "plain", G_plain, "output in postscript plain hexdump style"))
	op.Add(new OptParser.Boolean("r", "revert", G_revert, "reverse operation: convert (or patch) hexdump into binary"))
	op.Add(new OptParser.String("s", "seek", G_seek, "[+][-]seek", "start at <seek> bytes abs. (or +: rel.) infile offset"))
	op.Add(new OptParser.Boolean("u", "", G_uppercase, "use uppercase hex letters"))
	op.Add(new OptParser.Boolean("h", "help", G_help, "", OptParser.OPT_HIDDEN))
	op.Add(new OptParser.Boolean("v", "version", G_version, "", OptParser.OPT_HIDDEN))

	try {
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
			Console.Write(op.Usage() "`n")
			exitapp _main.Return()
		}

		if (G_version) {
			Console.Write(G_VERSION_INFO.NAME "/" G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD "`n")
			exitapp _main.Return()
		}

		; Plausibility checks
		if (files.MaxIndex() > 2)
			throw Exception("",, 1)

		if (G_bits && (G_plain || G_revert)) {
			G_bits := false
			if (_main.Logs(Logger.Warning))
				_main.Warning("-b is incompatible with -p (" G_plain ") or -r (" G_revert "); -b is ignored")
		}

		if (G_revert && (G_autoskip || G_bits || G_groupsize || G_length))
			throw Exception("",, -1)

		; Handle defaults
		if (G_plain && G_cols = "") {
			G_cols := 30
			if (_main.Logs(Logger.Info))
				_main.Info("-p: Setting 'cols' to 30")
		} else if (G_bits) {
			if (G_cols = "")
				G_cols := 6
			if (_main.Logs(Logger.Info))
				_main.Info("-b: Setting 'cols' to 6")
			if (G_groupsize = "")
				G_groupsize := 1
			if (_main.Logs(Logger.Info)) {
				_main.Info("-b: Setting 'groupsize' to 1")
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
			generate_binary(infile, outfile)
		else
			generate_dump(infile, outfile)

	} catch _ex {
		if (_ex.Message <> "")
			Console.Write(_ex.Message "`n")
		Console.Write(op.Usage() "`n")

		RC := _ex.Extra
	}

exitapp _main.Exit(RC)

generate_dump(infile, outfile) {
	_log := new Logger("app.xxd." A_ThisFunc)

	if (_log.Logs(Logger.Input)) {
		_log.Input("infile", infile)
		_log.Input("outfile", outfile)
	}

	buf_size := VarSetCapacity(buffer, 0xFFFF)
	if (_log.Logs(Logger.Finest))
		_log.Finest("buf_size", buf_size)
	cur_code_sum := 0 ; Sum of all bytes in current line
	nul_line_count := 0 ; Number of consecutive nul lines
	cur_octets_count := 0 ; Number of octets in current line
	total_octets_count := 0 ; Number of printed octets

	try {
		_in := open_infile(infile)
		_out := open_outfile(outfile)
		if (G_seek) {
			RegExMatch(G_seek, "(?P<plus>\+)?(?P<minus>-)?(?P<number>\d+)", __seek_)
			if (_log.Logs(Logger.Finest)) {
				_log.Finest("__seek_plus", __seek_plus)
				_log.Finest("__seek_minus", __seek_minus)
				_log.Finest("__seek_number", __seek_number)
			}
			if (__seek_plus && !__seek_minus)
				_in.Seek(__seek_number, 1)
			else if (!_seek_plus && __seek_minus)
				_in.Seek(__seek_minus __seek_number, 2)
			else
				_in.Seek(__seek_number)
			if (_log.Logs(Logger.Finest)) {
				_log.Finest("_in.Position", _in.Position)
			}
		} else
			G_seek := 0

		_offset := _in.Position
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
			if (!G_plain) { ; Fill right hand size with readable chars
				if (byte >= 32 && byte < 127)
					out_line_right .= Chr(byte)
				else
					out_line_right .= "."
				if (!Mod(cur_octets_count, G_groupsize) && cur_octets_count < G_cols && G_groupsize <> 0) { ; Grouping 
					out_line .= " "
				}
			}
			if (!Mod(cur_octets_count, G_cols)) { ; Max no of cols reached
				if (G_autoskip)
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

	line_expr := "iO)^"
	if (!G_plain)
		line_expr .= "([0-9a-z]+): "
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
				OutputDebug Invalid line: #%A_Index%: %line%
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
			i := FileOpen(Console.hStdIn, "h `n")
		else
			i := FileOpen(infile, "r")
	catch _ex 
		throw Exception("xxd: Failed to open file: " infile,, 3)

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
			o := FileOpen(Console.hStdOut, "h")
		else
			o := FileOpen(outfile, mode)
	catch _ex
		throw Exception("xxd: Failed to open file: " outfile,, 4)

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
	
	d1 := value // 16
	d2 := Mod(value, 16)

	i := (G_bits ? 3 : (G_uppercase ? 2 : 1))

	return DIGIT_TAB[d1, i] . DIGIT_TAB[d2, i]
}

offset(value) {
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
		return _log.Exit("")

	i := (G_uppercase ? 2 : 1)
	n := StrLen(value+0) - 1
	hex := ""

	while (n > 0) {
		f := 16**(n--)
		d := value // f
		value -= d * f
		hex .= DIGIT_TAB[d, i]
	}

	return SubStr("0000000" hex . DIGIT_TAB[Mod(value, 16), i], -6) ": "
}
