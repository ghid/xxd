#NoEnv
SetBatchLines -1

#Include <logging>
#Include <optparser>
#Include <system>
#Include <console>
#Include <string>
#Include <arrays>

Main:
	_main := new Logger("app.xxd.Main")

	; Define Command Parser Options as Super global vars to make them everywhere accessable
	global G_autoskip := false
		 , G_bits := false
		 , G_cols := ""
		 , G_groupsize := 2
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
	op.Add(new OptParser.String("g", "groupsize", G_groupsize, "bytes", "number of octets per group in normal output. Default 2",, G_groupsize, 2))
	op.Add(new OptParser.String("l", "len", G_length, "len", "stop after <len> octets"))
	op.Add(new OptParser.Boolean("p", "plain", G_plain, "output in postscript plain hexdump style"))
	op.Add(new OptParser.Boolean("r", "revert", G_revert, "reverse operation: convert (or patch) hexdump into binary"))
	op.Add(new OptParser.String("s", "seek", G_seek, "[+|-]seek", "start at <seek> bytes abs. (or +: rel.) infile offset"))
	op.Add(new OptParser.Boolean("u", "", G_uppercase, "use uppercase hex letters"))
	op.Add(new OptParser.Boolean("h", "help", G_help, "", OptParser.OPT_HIDDEN))

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

		if (G_help)
			Console.Write(op.Usage() "`n")

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
		} else if (G_cols = "") {
			G_cols := 16
			if (_main.Logs(Logger.Info))
				_main.Info("Setting 'cols' to default " G_cols)
		}

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

	buf_size := VarSetCapacity(buffer, 4096)
	if (_log.Logs(Logger.Finest))
		_log.Finest("buf_size", buf_size)
	offset := 0
	try {
		_in := open_infile(infile)
		_out := open_outfile(outfile)
		while (!_in.AtEOF) {
			bytes_read := _in.RawRead(buffer, buf_size)
			out_line := offset.AsHex(String.ASHEX_NOPREFIX).Pad(String.PAD_LEFT, 7, "0") ": "
			out_line_right := ""
			loop %bytes_read% {
				byte := NumGet(buffer, A_Index-1, "UChar")
				out_line .= byte.AsHex(String.ASHEX_NOPREFIX, 2)
				if (byte > 32 && byte < 127)
					out_line_right .= Chr(byte)
				else
					out_line_right .= "."
				if (!Mod(A_Index, G_groupsize))
					out_line .= " "
				if (!Mod(A_Index, G_cols)) {
					_out.WriteLine(out_line " " out_line_right)
					out_line := (offset+=G_cols).AsHex(String.ASHEX_NOPREFIX).Pad(String.PAD_LEFT, 7, "0") ": "
					out_line_right := ""
				}
			}
		}
		if (out_line_right) {
			cols_left := G_cols - Mod(bytes_read, G_cols)
			_out.WriteLine(out_line " ".Repeat(cols_left * 2 + cols_left // G_groupsize + 1) . out_line_right)
		}
	} finally {
		if (_in)
			_in.Close()
		if (_out)
			_out.Close()
	}

	return _log.Exit()
}

open_infile(infile) {
	_log := new Logger("app.xxd." A_ThisFunc)

	if (_log.Logs(Logger.Input))
		_log.Input("infile", infile)

	try
		i := FileOpen(infile, "r")
	catch _ex 
		throw Exception("xxd: Failed to open file: " infile,, 3)

	return _log.Exit(i)
}

open_outfile(outfile) {
	_log := new Logger("app.xxd." A_ThisFunc)

	if (_log.Logs(Logger.Input))
		_log.Input("outfile", outfile)

	try
		if (outfile = "" || outfile = "-")
			o := FileOpen(Console.hStdOut, "h")
		else
			o := FileOpen(outfile, "w")
	catch _ex
		throw Exception("xxd: Failed to open file: " outfile,, 4)

	return _log.Exit(o)
}