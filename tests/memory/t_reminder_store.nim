import unittest
import std/[os, times]
import donkey/adapters/memory/md_file
import donkey/core/types

suite "scheduleReminder / loadDueReminders / deleteReminder":

  test "reminder criado fica em disco":
    let tmp = getTempDir() / "donkey_rem_test1"
    defer: removeDir(tmp)
    let mem = MdFileAdapter(paddocksDir: tmp)
    let uid = UserId("user-a")
    mem.ensurePaddock(uid)
    let past = getTime().toUnix() - 60
    let id = mem.scheduleReminder(uid, "ckTelegram", past, "standup!")
    check id.len > 0
    let due = mem.loadDueReminders()
    check due.len == 1
    check due[0]["message"].getStr() == "standup!"
    check due[0]["channel"].getStr() == "ckTelegram"

  test "reminder futuro não aparece como due":
    let tmp = getTempDir() / "donkey_rem_test2"
    defer: removeDir(tmp)
    let mem = MdFileAdapter(paddocksDir: tmp)
    let uid = UserId("user-b")
    mem.ensurePaddock(uid)
    let future = getTime().toUnix() + 3_600
    discard mem.scheduleReminder(uid, "ckTelegram", future, "futuro")
    check mem.loadDueReminders().len == 0

  test "deleteReminder remove o arquivo":
    let tmp = getTempDir() / "donkey_rem_test3"
    defer: removeDir(tmp)
    let mem = MdFileAdapter(paddocksDir: tmp)
    let uid = UserId("user-c")
    mem.ensurePaddock(uid)
    let past = getTime().toUnix() - 10
    let id = mem.scheduleReminder(uid, "ckTelegram", past, "deleteme")
    check mem.loadDueReminders().len == 1
    mem.deleteReminder(uid, id)
    check mem.loadDueReminders().len == 0

  test "múltiplos usuários — só due aparecem":
    let tmp = getTempDir() / "donkey_rem_test4"
    defer: removeDir(tmp)
    let mem = MdFileAdapter(paddocksDir: tmp)
    let u1  = UserId("user-x")
    let u2  = UserId("user-y")
    mem.ensurePaddock(u1)
    mem.ensurePaddock(u2)
    discard mem.scheduleReminder(u1, "ckTelegram", getTime().toUnix() - 5, "due")
    discard mem.scheduleReminder(u2, "ckTelegram", getTime().toUnix() + 999, "future")
    let due = mem.loadDueReminders()
    check due.len == 1
    check due[0]["message"].getStr() == "due"
