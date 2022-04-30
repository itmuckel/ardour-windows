#!/usr/bin/env bash

# we assume this script is <ardour-build-src>/tools/x-win/compile.sh
pushd "`/usr/bin/dirname \"$0\"`" > /dev/null; this_script_dir="`pwd`"; popd > /dev/null
cd "$this_script_dir/../../src"

test -f gtk2_ardour/wscript || exit 1

: ${XARCH=i686} # or x86_64
: ${ROOT=/home/ardour}
: ${MAKEFLAGS=-j4}
: ${ENABLE_OPT=ON}

if test "$XARCH" = "x86_64" -o "$XARCH" = "amd64"; then
	echo "Target: 64bit Windows (x86_64)"
	XPREFIX=x86_64-w64-mingw32
	WARCH=w64
	DEBIANPKGS="gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix" # <-- for std::mutex on Windows
else
	echo "Target: 32 Windows (i686)"
	XPREFIX=i686-w64-mingw32
	WARCH=w32
	DEBIANPKGS="gcc-mingw-w64-i686 g++-mingw-w64-i686 mingw-w64-tools mingw32"
fi

: ${PREFIX=${ROOT}/win-stack-$WARCH}

# for debug build: remove --optimize
# ptformat reads and parses ProTools https://www.avid.com/pro-tools session files.
# for free/demo version: add --freebie
if test -z "${ARDOURCFG}"; then
	if test -f ${PREFIX}/include/pa_asio.h; then
		ARDOURCFG="--dist-target=mingw --windows-vst --ptformat --with-backends=jack,dummy,portaudio --cxx11"
	else
		ARDOURCFG="--dist-target=mingw --windows-vst --ptformat --with-backends=jack,dummy --cxx11"
	fi
fi

# if test "$ENABLE_OPT" == "ON"; then
# 	ARDOURCFG="$ARDOURCFG --optimize"
# fi

if [ "$(id -u)" = "0" ]; then
	apt-get -qq -y install build-essential \
		${DEBIANPKGS} \
		git autoconf automake libtool pkg-config yasm python

	#fixup mingw64 ccache for now
	if test -d /usr/lib/ccache -a -f /usr/bin/ccache; then
		export PATH="/usr/lib/ccache:${PATH}"
		cd /usr/lib/ccache
		test -L ${XPREFIX}-gcc || ln -s ../../bin/ccache ${XPREFIX}-gcc
		test -L ${XPREFIX}-g++ || ln -s ../../bin/ccache ${XPREFIX}-g++
		cd - > /dev/null
	fi
fi

################################################################################
set -e
unset PKG_CONFIG_PATH
export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig

export CC=${XPREFIX}-gcc
export CXX=${XPREFIX}-g++
export CPP=${XPREFIX}-cpp
export AR=${XPREFIX}-ar
export LD=${XPREFIX}-ld
export NM=${XPREFIX}-nm
export AS=${XPREFIX}-as
export STRIP=${XPREFIX}-strip
export WINRC=${XPREFIX}-windres
export RANLIB=${XPREFIX}-ranlib
export DLLTOOL=${XPREFIX}-dlltool

if grep -q optimize <<<"$ARDOURCFG"; then
	OPT=""
else
	#debug-build luabindings.cc, has > 60k symbols.
	# -Wa,-mbig-obj has an unreasonable long build-time
	# -Og to the rescue.
	OPT=" -Og"
fi

CFLAGS="-mstackrealign$OPT" \
CXXFLAGS="-mstackrealign$OPT" \
LDFLAGS="-L${PREFIX}/lib" \
DEPSTACK_ROOT="$PREFIX" \
./waf configure \
	--keepflags \
	--dist-target=mingw \
	--also-include=${PREFIX}/include \
	$ARDOURCFG \
	--prefix=${PREFIX} \
	--libdir=${PREFIX}/lib

./waf ${CONCURRENCY}

if [ "$(id -u)" = "0" ]; then
	apt-get -qq -y install gettext
fi
echo " === build complete, creating translations"
./waf i18n
echo " === done"
