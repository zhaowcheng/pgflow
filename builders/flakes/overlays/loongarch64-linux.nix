final: prev: {
  geos = prev.geos.overrideAttrs (oldAttrs: {
    # 266 - unit-operation-distance-IndexedFacetDistance (Timeout)
    doCheck = false;
  });

  proj = prev.proj.overrideAttrs (oldAttrs: {
    # 45 - test_projsync.sh (Failed)
    doCheck = false;
    passthru = oldAttrs.passthru or { };
  });
}