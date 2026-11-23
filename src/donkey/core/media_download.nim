## media_download.nim — Generic file download utilities for channel adapters.
##
## Provides:
##   - downloadUrlAsBytes: downloads any URL to seq[byte]
##   - downloadUrlToFile: downloads any URL to local file path
##   - saveFileToDisk: saves seq[byte] to a file in a directory

import std/[os, strutils]
import ../ports/http
import ../ports/channel
import ./pipeops

export channel.FileDownload

func extractFileName*(url: string): string =
  ## Extracts file name from URL (last path segment).
  let parts = url.split('/')
  if parts.len > 0:
    result = parts[^1].split('?')[0]  # Remove query params
  if result.len == 0:
    result = "download"

func extractMimeType*(url: string): string =
  ## Guesses MIME type from file extension in URL.
  let fileName = url.extractFileName.toLowerAscii
  if fileName.endsWith(".jpg") or fileName.endsWith(".jpeg"): "image/jpeg"
  elif fileName.endsWith(".png"): "image/png"
  elif fileName.endsWith(".gif"): "image/gif"
  elif fileName.endsWith(".webp"): "image/webp"
  elif fileName.endsWith(".pdf"): "application/pdf"
  elif fileName.endsWith(".txt"): "text/plain"
  elif fileName.endsWith(".md"): "text/markdown"
  elif fileName.endsWith(".json"): "application/json"
  elif fileName.endsWith(".zip"): "application/zip"
  elif fileName.endsWith(".mp3"): "audio/mpeg"
  elif fileName.endsWith(".ogg"): "audio/ogg"
  elif fileName.endsWith(".wav"): "audio/wav"
  elif fileName.endsWith(".mp4"): "video/mp4"
  elif fileName.endsWith(".webm"): "video/webm"
  else: "application/octet-stream"

func toBytes(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i in 0 ..< s.len:
    result[i] = byte(s[i])

proc fetchBytes*(http: HttpPort; url: string;
                 headers: seq[HttpHeader]): Result[seq[byte], string] =
  ## GETs `url` and returns the body as bytes. Any non-2xx status is an
  ## error — otherwise an error page (404 HTML, 401 JSON) would be handed
  ## to the caller as if it were the requested file.
  try:
    let resp = ? http.get(url, headers)
    if resp.status < 200 or resp.status >= 300:
      return err("download failed: HTTP " & $resp.status)
    ok(resp.body.toBytes)
  except CatchableError as e:
    err("fetchBytes: " & e.msg)

proc downloadUrlAsBytes*(http: HttpPort; url: string): Result[seq[byte], string] =
  ## Downloads any URL and returns raw bytes as seq[byte].
  http.fetchBytes(url, @[])

proc downloadUrl*(http: HttpPort; url: string;
                  fileName = ""): Result[FileDownload, string] =
  ## Downloads a file from URL and returns FileDownload.
  let data = ? http.downloadUrlAsBytes(url)
  let name = if fileName.len > 0: fileName else: url.extractFileName
  let mime = url.extractMimeType
  
  ok(FileDownload(
    fileName: name,
    fileSize: data.len.int64,
    mimeType: mime,
    localPath: "",
    data: data
  ))

proc saveFileToDisk*(download: var FileDownload; directory: string): Result[string, string] =
  ## Saves downloaded file to disk in specified directory.
  ## Returns the full path of the saved file.
  try:
    if not dirExists(directory):
      createDir(directory)
    
    # Ensure unique file name
    var finalPath = directory / download.fileName
    var counter = 1
    ## A dangling symlink is not reported by fileExists, but writing through it
    ## would follow the link target. Treat it as an occupied name.
    while fileExists(finalPath) or symlinkExists(finalPath):
      let nameParts = download.fileName.split('.')
      if nameParts.len > 1:
        let ext = nameParts[^1]
        let base = nameParts[0 .. ^2].join(".")
        finalPath = directory / (base & "_" & $counter & "." & ext)
      else:
        finalPath = directory / (download.fileName & "_" & $counter)
      inc(counter)
    
    # Write bytes to file
    var content = newString(download.data.len)
    for i in 0 ..< download.data.len:
      content[i] = cast[char](download.data[i])
    writeFile(finalPath, content)
    
    download.localPath = finalPath
    ok(finalPath)
  except CatchableError as e:
    err("saveFileToDisk: " & e.msg)
