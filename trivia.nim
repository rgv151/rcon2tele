import os, random, asyncdispatch, asyncnet, strutils, websocket, json

type
  Trivia* = ref object
    isRunning: bool
    isAnswered: bool
    questionDir: string
    questionFiles: seq[string]
    question: string
    answers: seq[string]
    ws: AsyncWebsocket
    rewards: seq[tuple[item: string, max: int]]
    rewardCount: int

proc loadQuestionFiles*(t: Trivia) =
  t.questionFiles = @[]
  for kind, path in walkDir(t.questionDir):
    t.questionFiles.add(path)

proc loadRewards(t: Trivia, file: string) =
  t.rewards = @[]
  let f = open(file)
  for line in f.lines:
    if not isNilOrEmpty(line):
      let
        reward = line.split('`')
        max_items = parseInt(reward[1])
      if max_items < 1:
        continue
      t.rewards.add((reward[0], max_items))
      echo "Loaded new reward: ", reward[0], " max items: ", reward[1]
  t.rewardCount = t.rewards.len
  f.close()

proc newTrivia*(dir: string, rewards: string, ws: AsyncWebsocket): Trivia =
  result = new(Trivia)

  result.questionDir = dir
  result.isRunning = false
  result.isAnswered = false
  result.question = ""
  result.answers = @[]

  result.ws = ws

  result.loadRewards(rewards)
  result.loadQuestionFiles()

proc isRunning*(t: Trivia): bool =
  return t.isRunning


proc getNewQuestion*(t: Trivia) =
  var
    file = open(random(t.questionFiles))
    question: string
    count = 0

  for _ in file.lines:
    inc(count)

  let rand = random(count)
  count = 0
  file.setFilePos(0)
  for line in file.lines:
    if count == rand:
      if isNilOrEmpty(line):
        t.getNewQuestion()

      question = line
      break
    inc(count)
  file.close()

  let tmp = question.split('`')
  t.question = tmp[0]
  t.answers = toLower(strip(tmp[1])).split('|')
  t.isAnswered = false

proc start*(t: Trivia) {.async.} =
  if t.isRunning:
    echo "The game is already running"
    return
  t.isRunning = true

  let cmd = %*{
    "Identifier": 10000,
    "Message": "say <color=yellow>Trivia game will starts in 15s, you have 20s to anwser the questions.. Have fun!</color>",
    "Name": "trivia"
  }
  await t.ws.sock.sendText($cmd, true)
  await sleepAsync(15_000)
  while t.isRunning:
    t.getNewQuestion()
    echo t.answers
    if not t.ws.sock.isClosed():
      let cmd = %*{
        "Identifier": 10000,
        "Message": "say Q: " & t.question,
        "Name": "trivia"
      }
      await t.ws.sock.sendText($cmd, true)
    await sleepAsync(20_000)

proc stop*(t: Trivia) =
  t.isRunning = false

proc matchAnswer*(t: Trivia, answer: string, userId: int) {.async.} =
  if not t.isRunning:
    return
  if t.isAnswered:
    return

  if toLower(strip(answer)) in t.answers:
    t.isAnswered = true

    var
      reward_index = random(t.rewardCount)
      reward_item = t.rewards[reward_index][0]
      reward_num = t.rewards[reward_index][1]
    if reward_num > 1:
      reward_num = random(reward_num) + 1
    let cmd = %*{
      "Identifier": 10000,
      "Message": "inventory.giveto \"" & $userId & "\" \"" & reward_item & "\" \"" & $reward_num & "\"",
      "Name": "trivia"
    }
    await t.ws.sock.sendText($cmd, true)