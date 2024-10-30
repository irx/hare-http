// License: 0BSD
// (c) 2023-2024 Max Mruszczak <u at one u x dot o r g>

use bufio;
use bytes;
use encoding::utf8;
use fmt;
use io;
use memio;
use net::uri;
use os;
use strconv;
use strings;

export type method = enum {
	GET,
	HEAD,
	POST,
	PUT,
	DELETE,
	CONNECT,
	OPTIONS,
	TRACE,
	PATCH,
};

export type header = struct {
	key: str, // header name; needs to be allocated / freed
	value: (str | []str | void), // header value; memory is borrowed from the content field
	content: []u8, // the OCTETs making up the value; needs to be allocated / freed
};

export type request = struct {
	method: method,
	uri: str,
	headers: []header,
	body: []u8,
};

export type response = struct {
	code: code,
	headers: []header,
	body: []u8,
};

export type message = (*request | *response);

export type malformed_header = !void;
export type malformed_startline = !void;

export fn tostr_method(m: method) const str = switch (m) {
case method::GET => return "GET";
case method::HEAD => return "HEAD";
case method::POST => return "POST";
case method::PUT => return "PUT";
case method::DELETE => return "DELETE";
case method::CONNECT => return "CONNECT";
case method::OPTIONS => return "OPTIONS";
case method::TRACE => return "TRACE";
case method::PATCH => return "PATCH";
};

export fn parse_method(s: str) (method | malformed_startline) = switch (s) {
case "GET" => return method::GET;
case "HEAD" => return method::HEAD;
case "POST" => return method::POST;
case "PUT" => return method::PUT;
case "DELETE" => return method::DELETE;
case "CONNECT" => return method::CONNECT;
case "OPTIONS" => return method::OPTIONS;
case "TRACE" => return method::TRACE;
case "PATCH" => return method::PATCH;
case => return malformed_startline;
};

@test fn method() void = {
	assert(method::GET == parse_method(tostr_method(method::GET))!);
	assert(method::GET == parse_method("GET")!);
};

export fn write_request(out: io::handle, req: *const request) (size | io::error) = {
	let z = 0z;
	z += fmt::fprintf(out, "{} {} HTTP/1.1\r\n",
		tostr_method(req.method),
		req.uri)?;
	for (let i = 0z; i < len(req.headers); i += 1)
		z += fmt::fprintf(out, "{}: {}\r\n",
			req.headers[i].key,
			req.headers[i].value as str)?;
	z += fmt::fprint(out, "\r\n")?;
	z += io::write(out, req.body)?;
	return z;
};

@test fn write_request() void = {
	let req = request {
		method = method::GET,
		uri = "/",
		headers = [],
		body = [],
	};
	write(os::stdout, &req)!;
	//finish(&req);
};

export fn write_response(out: io::handle, res: *const response) (size | io::error) = {
	let z = 0z;
	z += fmt::fprintf(out, "HTTP/1.1 {} {}\r\n",
		res.code: u16, reason_str(res.code))?;
	for (let i = 0z; i < len(res.headers); i += 1)
		z += fmt::fprintf(out, "{}: {}\r\n",
			res.headers[i].key,
			res.headers[i].value as str)?;
	z += fmt::fprint(out, "\r\n")?;
	z += io::write(out, res.body)?;
	return z;
};

// Writes a [[message]] to a given io handle
export fn write(out: io::handle, msg: const message) (size | io::error) = {
	let z = 0z;
	const headers = match (msg) {
	case let req: *request =>
		z += fmt::fprintf(out, "{} {} HTTP/1.1\r\n",
			tostr_method(req.method),
			req.uri)?;
		yield req.headers;
	case let res: *response =>
		z += fmt::fprintf(out, "HTTP/1.1 {} {}\r\n",
			res.code: u16, reason_str(res.code))?;
		yield res.headers;
	};
	for (let i = 0z; i < len(headers); i += 1)
		match (headers[i].value) {
		case let val: str =>
			z += fmt::fprintf(out, "{}: {}\r\n",
				headers[i].key, val)?;
		case let vals: []str =>
			z += fmt::fprintf(out, "{}:", headers[i].key)?;
			for (let j = 0z; j < len(vals); j += 1)
				z += fmt::fprintf(out, " {};", vals[j])?;
			z += fmt::fprint(out, "\r\n")?;
		case void =>
			z += fmt::fprintf(out, "{}:\r\n", headers[i].key)?;
		};
	z += fmt::fprint(out, "\r\n")?;
	const body = match (msg) {
	case let req: *request => yield req.body;
	case let res: *response => yield res.body;
	};
	z += io::write(out, body)?;
	return z;
};

// Dumps [[message]] into a string. Must be freed after use.
export fn tostr(msg: const message) str = {
	let s = memio::dynamic();
	write(&s, msg)!;
	return memio::string(&s)!;
};

@test fn tostr() void = {
	let req = request {
		method = method::GET,
		uri = "/",
		headers = [],
		body = strings::toutf8("hello"),
	};
	//defer finish(&req: *message);
	let s = tostr(&req);
	defer free(s);
	assert(s == "GET / HTTP/1.1\r\n\r\nhello");
};

// Frees memory allocated for [[message]].
export fn finish(msg: message) void = {
	const headers = match (msg) {
	case let req: *request =>
		free(req.uri);
		free(req.body);
		yield &req.headers;
	case let res: *response =>
		free(res.body);
		yield &res.headers;
	};
	for (let i = 0z; i < len(headers); i += 1) {
		free(headers[i].key);
		free(headers[i].content);
		if (headers[i].value is []str)
			free(headers[i].value as []str);
	};
	free(*headers);
};

@test fn allocate() void = {
	let req = request {
		method = method::GET,
		uri = strings::dup("/index.html"),
		headers = alloc([], 4),
		body = alloc([], 4),
	};
	const content: []u8 = alloc(['v', 'a', 'l', 'u', 'e'], 5);
	append(req.headers,
		header {
			key = strings::dup("key"),
			content = content,
			value = strings::fromutf8(content) as str,
		}
	);
	finish(&req);
};

// Creates a [[header]] structure. Needs to be freed as a part of [[message]]
// using [[finish]].
export fn newheader(key: const str, value: const str...) header = {
	let hdr = header {
		key = strings::dup(key),
		value = void,
		content = [],
	};
	switch (len(value)) {
	case 0z =>
		return hdr;
	case 1z =>
		hdr.content = alloc(strings::toutf8(value[0])...);
		hdr.value = strings::fromutf8(hdr.content)!;
		return hdr;
	case =>
		yield;
	};
	let fields: []str = [];
	let bounds: [](size,size) = alloc([(0,0)...], len(value));
	defer free(bounds);
	for (let i = 0z; i < len(value); i += 1) {
		const bytes = strings::toutf8(value[i]);
		bounds[i].0 = switch (len(hdr.content)) {
		case 0z =>
			hdr.content = alloc(bytes...);
			yield 0z;
		case =>
			// add delimiter
			append(hdr.content, ';');
			const start = len(hdr.content);
			append(hdr.content, bytes...);
			yield start;
		};
		bounds[i].1 = len(hdr.content);
	};
	for (const b .. bounds) {
		append(fields, strings::fromutf8(hdr.content[b.0..b.1])!);
	};
	hdr.value = fields;
	//fmt::printfln("content: {}", strings::fromutf8(hdr.content)!)!;
	//fmt::printfln("field 1: {}", fields[0])!;
	return hdr;
};

@test fn newheader() void = {
	let req = request {
		method = method::GET,
		uri = strings::dup("/path"),
		headers = [],
		body = [],
	};
	append(req.headers, newheader("Authorization", "Bearer token"));
	append(req.headers, newheader("Multi-Field-Header", "first field", "second field"));
	finish(&req);
};

// Adds a new [[header]] to the [[message]].
export fn addheader(msg: message, key: const str, value: const str...) void = {
	let hdrs = match (msg) {
	case let req: *request =>
		yield &req.headers;
	case let res: *response =>
		yield &res.headers;
	};
	append(hdrs, newheader(key, value...));
};

@test fn addheader() void = {
	let req = request {
		method = method::GET,
		uri = strings::dup("/path"),
		headers = [],
		body = [],
	};
	addheader(&req, "Content-Type", "text");
	addheader(&req, "Authorization", "Bearer token");
	addheader(&req, "Multi-Field-Header", "first field", "second field");
	const body: []u8 = alloc([0...], 1024);
	req.body = body;
	addheader(&req, "Length", "1024");
	addheader(&req, "Very-Long-Header",
		"first",
		"second",
		"third",
		"fourth",
		"fifth");
	finish(&req);
};

// Creates a [[header]] structure by parsing a serialized header.  Needs to be
// freed as a part of a [[message]] using [[finish]].
export fn parseheader(src: const []u8) (header | malformed_header | utf8::invalid) = {
	if (!bytes::contains(src, ':'))
		return malformed_header;
	const kv = bytes::cut(src, ':');
	let hdr = header {
		key = strings::dup(strings::fromutf8(bytes::trim(kv.0, ' '))?),
		content = alloc(bytes::trim(kv.1, ' ')...),
		value = void,
	};
	// no value fields
	if (len(hdr.content) == 0)
		return hdr;
	// cleanup in case of failure
	let success = false;
	let values: []str = [];
	defer if (!success) {
		free(hdr.key);
		free(hdr.content);
		free(values);
	};
	// single value field
	if (!bytes::contains(hdr.content, ';')) {
		hdr.value = strings::fromutf8(hdr.content)?;
		success = true;
		return hdr;
	};
	// multiple values field
	const del: [1]u8 = [';'];
	let tok = bytes::tokenize(hdr.content, del);
	for (true) match (bytes::next_token(&tok)) {
	case let b: []u8 =>
		append(values, strings::fromutf8(bytes::trim(b, ' '))?);
	case done =>
		hdr.value = values;
		success = true;
		return hdr;
	};
};

fn parsestartline(src: const []u8) (message | utf8::invalid) = {
	let res: *response = alloc(response{...});
	return res;
};

fn parserequestline(req: *request, src: const []u8) (*request | utf8::invalid | malformed_startline) = {
	const del: [1]u8 = [' '];
	let tok = bytes::tokenize(src, del);
	req.method = match (bytes::next_token(&tok)) {
	case let b: []u8 =>
		yield parse_method(strings::fromutf8(b)?)?;
	case done =>
		return malformed_startline;
	};
	req.uri = match (bytes::next_token(&tok)) {
	case let b: []u8 =>
		yield strings::dup(strings::fromutf8(b)?);
	case done =>
		return malformed_startline;
	};
	// TODO read HTTP version
	return req;
};

@test fn requestline() void = {
	const line: str = "GET / HTTP/1.1";
	let req = request {...};
	parserequestline(&req, strings::toutf8(line))!;
	assert(req.method == method::GET);
	assert(req.uri == "/");
	const line: str = "POST /images HTTP/1.1";
	parserequestline(&req, strings::toutf8(line))!;
	assert(req.method == method::POST);
	assert(req.uri == "/images");
};

fn parsestatusline(res: *response, src: const []u8) (*response | utf8::invalid | malformed_startline) = {
	const del: [1]u8 = [' '];
	let tok = bytes::tokenize(src, del);
	match (bytes::next_token(&tok)) {
	case []u8 => yield; // TODO read HTTP version
	case done =>
		return malformed_startline;
	};
	res.code = match (bytes::next_token(&tok)) {
	case let b: []u8 =>
		yield match (strconv::stou16(strings::fromutf8(b)?, strconv::base::DEC)) {
		case let num: u16 =>
			yield num: code;
		case =>
			return malformed_startline;
		};
	case done =>
		return malformed_startline;
	};
	return res;
};

@test fn statusline() void = {
	const line = "HTTP/1.1 200 OK";
	let res = response {...};
	parsestatusline(&res, strings::toutf8(line))!;
	assert(res.code == 200);
	res.code = 404;
	const msg = tostr(&res);
	defer free(msg);
	// TODO check generated status line
};

fn read_request(in: io::handle) (request | io::error | utf8::invalid | malformed_startline | malformed_header) = {
	let req = request {...};
	const del: [2]u8 = ['\r', '\n'];
	let line = bufio::read_tok(in, del...)?;
	if (line is io::EOF)
		return malformed_startline;
	parserequestline(&req, line as []u8)?;
	let finished = false;
	defer if (!finished) finish(&req);
	for (true) match (bufio::read_tok(in, del...)?) {
	case io::EOF =>
		break;
	case let line: []u8 =>
		if (len(line) == 0z)
			break;
		append(req.headers, parseheader(line)?);
	};
	finished = true;
	return req;
};

@test fn read_request() void = {
	let req = request {...};
	req.method = method::POST;
	req.uri = "/thing";
	const msg = tostr(&req);
	defer free(msg);
	let req2 = read_request(&memio::fixed(strings::toutf8(msg)))!;
	defer finish(&req2);
	assert(req2.method == req.method);
	assert(req2.uri == req.uri);
};

fn read_response(in: io::handle) (response | io::error | utf8::invalid | malformed_startline | malformed_header) = {
	let res = response {...};
	const del: [2]u8 = ['\r', '\n'];
	let line = bufio::read_tok(in, del...)?;
	if (line is io::EOF)
		return malformed_startline;
	parsestatusline(&res, line as []u8)?;
	let finished = false;
	defer if (!finished) finish(&res);
	for (true) match (bufio::read_tok(in, del...)?) {
	case io::EOF =>
		break;
	case let line: []u8 =>
		if (len(line) == 0z)
			break;
		append(res.headers, parseheader(line)?);
	};
	finished = true;
	return res;
};

@test fn read_response() void = {
	let res = response {...};
	res.code = 404;
	const msg = tostr(&res);
	defer free(msg);
	let res2 = read_response(&memio::fixed(strings::toutf8(msg)))!;
	defer finish(&res2);
	assert(res2.code == res.code);
};
