// License: 0BSD
// (c) 2023 Max Mruszczak <u at one u x dot o r g>

use bufio;
use fmt;
use io;
use memio;
use net::uri;
use os;
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
	key: str,
	value: (str | []str | void),
	content: []u8,
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

@test fn tostr_method() void = {
	let m = method::GET;
	assert(tostr_method(m) == "GET");
	let name = strings::dup(tostr_method(m));
	defer free(name);
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
	//finish(&req: *message);
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
				z += fmt::fprintf(out, " {};")?;
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

export fn finish(msg: message) void = {
	const headers = match (msg) {
	case let req: *request =>
		free(req.uri);
		free(req.body);
		yield req.headers;
	case let res: *response =>
		free(res.body);
		yield res.headers;
	};
	for (let i = 0z; i < len(headers); i += 1) {
		free(headers[i].key);
		free(headers[i].content);
	};
	free(headers);
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
