"""
School-specific parsing profiles.

Each profile customises heuristic parameters for a particular school's
casebook formatting style.  The registry maps normalised school slugs
(as produced by scanner.infer_school_from_folder) to CasebookProfile
instances.

To add a new school:
  1. Add its slug → folder-name mapping to config.yaml :: known_schools
  2. Create a factory here (or in a new profile module) and register it below.
"""

from pipeline.parsers.profiles.default import (
    CasebookProfile,
    DEFAULT_SECTION_HEADERS,
    DEFAULT_TOC_INDICATORS,
    create_default_profile,
    create_booth_profile,
    create_yale_profile,
    create_rocketblocks_profile,
)

# ── Profile registry ──────────────────────────────────────────────────────────
# Keys must match the school slugs produced by scanner.infer_school_from_folder.
_PROFILE_REGISTRY: dict[str, CasebookProfile] = {
    "booth":        create_booth_profile(),
    "yale":         create_yale_profile(),
    "ross":         create_yale_profile(),   # Ross uses a similar format to Yale
    "darden":       create_yale_profile(),
    "rocketblocks": create_rocketblocks_profile(),
}


def get_profile(school_name: str) -> CasebookProfile:
    """Return the CasebookProfile for the given school slug, or the default."""
    return _PROFILE_REGISTRY.get(school_name.lower(), create_default_profile())


def apply_config_overrides(profile: CasebookProfile, config) -> CasebookProfile:
    """
    Merge school_overrides from config.yaml into a profile.

    This lets operators tweak profiles without touching Python source.
    """
    overrides = getattr(config, "school_overrides", None)
    if overrides is None:
        return profile

    school_overrides = getattr(overrides, profile.name, None)
    if school_overrides is None:
        return profile

    for key, value in vars(school_overrides).items():
        if hasattr(profile, key):
            setattr(profile, key, value)

    return profile
