"""Tests for school-email domain allowlist."""

import pytest

from webapp.auth.users import InvalidEmailDomain, validate_email


def test_yale_edu_allowed():
    assert validate_email("student@yale.edu") == "student@yale.edu"


def test_umich_edu_allowed():
    assert validate_email("rossmba@umich.edu") == "rossmba@umich.edu"


def test_booth_guest_allowed():
    assert validate_email("acannata@chicagobooth.edu") == "acannata@chicagobooth.edu"


def test_other_booth_rejected():
    with pytest.raises(InvalidEmailDomain, match="invited"):
        validate_email("other@chicagobooth.edu")


def test_random_domain_rejected():
    with pytest.raises(InvalidEmailDomain):
        validate_email("user@gmail.com")
