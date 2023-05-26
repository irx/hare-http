.POSIX:
.SUFFIXES:
.PHONY: check install

HARE = hare
HAREFLAGS =
HAREDOC = haredoc

DESTDIR =
PREFIX = /usr/local
SRCDIR = ${PREFIX}/src
HARESRCDIR = ${SRCDIR}/hare
THIRDPARTYDIR = ${HARESRCDIR}/third-party

check:
	${HARE} test

install:
	mkdir -p "${DESTDIR}${THIRDPARTYDIR}/net/http"
	cp net/http/*.ha "${DESTDIR}${THIRDPARTYDIR}/net/http/"
