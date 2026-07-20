"""Monokai Pro Ristretto Filter — Pygments style for light and dark themes."""

from pygments.style import Style
from pygments.token import (
    Comment, Error, Keyword, Literal, Name, Number, Operator, Punctuation,
    String, Token, Text,
)


class RistrettoLightStyle(Style):
    background_color = '#fefaf9'
    styles = {
        Token:              '#5b5353',
        Text.Whitespace:    '#5b5353',
        Comment:            'italic #a59c9b',
        Keyword:            '#e14775',
        Keyword.Constant:   '#7058be',
        Keyword.Type:       '#e14775',
        Operator:           '#e14775',
        Operator.Word:      '#e14775',
        Punctuation:        '#5b5353',
        Name:               '#5b5353',
        Name.Builtin:       '#1c8ca8',
        Name.Builtin.Pseudo:'#e16032',
        Name.Function:      '#269d69',
        Name.Function.Magic:'#269d69',
        Name.Class:         '#269d69',
        Name.Decorator:     '#1c8ca8',
        Name.Exception:     '#1c8ca8',
        Name.Tag:           '#1c8ca8',
        Name.Attribute:     '#1c8ca8',
        String:             '#cc7a0a',
        Number:             '#7058be',
        Literal:            '#7058be',
        Error:              '#e14775',
    }


class RistrettoDarkStyle(Style):
    background_color = '#403838'
    styles = {
        Token:              '#fff1f3',
        Text.Whitespace:    '#fff1f3',
        Comment:            'italic #72696a',
        Keyword:            '#f06883',
        Keyword.Constant:   '#9ca9eb',
        Keyword.Type:       '#f06883',
        Operator:           '#f06883',
        Operator.Word:      '#f06883',
        Punctuation:        '#fff1f3',
        Name:               '#fff1f3',
        Name.Builtin:       '#85dacc',
        Name.Builtin.Pseudo:'#f38d70',
        Name.Function:      '#adda78',
        Name.Function.Magic:'#adda78',
        Name.Class:         '#adda78',
        Name.Decorator:     '#85dacc',
        Name.Exception:     '#85dacc',
        Name.Tag:           '#85dacc',
        Name.Attribute:     '#85dacc',
        String:             '#f9cc6c',
        Number:             '#9ca9eb',
        Literal:            '#9ca9eb',
        Error:              '#f06883',
    }
