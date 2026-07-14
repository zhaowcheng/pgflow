{ stdenv, fetchurl, lib, autoreconfHook, autoconf, automake, libtool }:

stdenv.mkDerivation rec {
  pname = "scws";
  version = "1.2.3";
  name = "${pname}-${version}";

  src = fetchurl {
    url = "http://www.xunsearch.com/scws/down/scws-${version}.tar.bz2";
    sha256 = "1x8s3yw7fi45cay5hahlma5qrjyq8zpczcbcn70g7ks2vk1hmmb0";
  };

  nativeBuildInputs = [ autoreconfHook autoconf automake libtool ];

  postInstall = ''
    # 创建 pkg-config 文件
    mkdir -p $out/lib/pkgconfig
    cat > $out/lib/pkgconfig/scws.pc << EOF
prefix=$out
libdir=$prefix/lib
includedir=$prefix/include/scws

Name: SCWS
Description: Simple Chinese Word Segmentation
Version: ${version}
Libs: -L$libdir -lscws
Cflags: -I$includedir
EOF
  '';

  meta = with lib; {
    description = "Simple Chinese Word Segmentation";
    homepage = "http://www.xunsearch.com/scws/";
    license = licenses.bsd3;
    platforms = platforms.unix;
    maintainers = [ ];
  };
}