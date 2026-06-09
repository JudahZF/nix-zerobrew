{ callPackage, zerobrew-src ? null, }: {
  zerobrew = callPackage ./zerobrew { inherit zerobrew-src; };
}
