# Third-Party Notices

Donkey includes behavior and test cases derived from the public history of the
projects below. The original code was not copied: each case was reimplemented
from the observed behavior of the external API, with its own tests.

## hermes-agent

- URL: https://github.com/nousresearch/hermes-agent
- Reference commit used for the Telegram pilot: `b3746e35dd`
- Derived material: diagnostic behaviors of the Telegram Bot API extracted from
  the project's fix history, and test cases written from those behaviors. See
  `docs/hermes-mining/telegram/CASES.md` for the case-by-case mapping and
  `docs/hermes-mining/TRACEABILITY.md` for the commit-to-test trail.

### License text

```
MIT License

Copyright (c) 2025 Nous Research

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
