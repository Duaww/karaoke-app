import 'dart:collection';
import 'dart:ffi';

import 'package:audioplayers/audio_cache.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart' as xml;
import 'dart:io' as io;
import 'package:xml_parser/xml_parser.dart';
import 'package:xml/xml.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

void main() {
  runApp(MyApp());
}

// Future<void> readFile() async {
//   String xmlString = await rootBundle.loadString('assets/data/lyrics.xml');
//   lyrics = xmlString;
// }

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MyMusicApp(),
    );
  }
}

class MyMusicApp extends StatefulWidget {
  @override
  _MyMusicAppState createState() => _MyMusicAppState();
}

class _MyMusicAppState extends State<MyMusicApp> {
  bool isPlay = false;
  IconData playBtn = Icons.play_arrow;

  String lyrics = ""; //lưu toàn bộ lyrics
  String lyricWillSing = ""; // câu tiếp theo sẽ hát
  String wordIsSinging = ""; // từ đang hát
  int timeOfWord = 0; // thời gian  của từ đang hát (microseconds)

  String previousWord = ""; // những từ trước từ đang hát
  String nextWord = "";
  int timeStartOfSentences = 0; // thời gian bắt đầu hát của một câu

  List<double> arrayTime = []; //lưu thời gian của từng từ
  List<String> arrayWord = []; // lưu từng trong lyrics

  Map<int, String> timeAndWord = {}; // lưu theo dạng  {time : word}
  // lưu thời gian bắt đầu và câu đang hát  {time : sentences}
  Map<int, String> sentences = {};
  Map<int, int> timeNotSing = {};
  int checkReadFile = 0; // check xử lý file 1 lần

  ScrollController _scrollController = new ScrollController();

  late AudioPlayer _player;
  late AudioCache cache;

  Duration position = new Duration();
  Duration musicLenght = new Duration();

  Widget slider() {
    return Container(
        width: 300,
        child: Slider.adaptive(
          activeColor: Colors.black,
          value: position.inSeconds.toDouble(),
          max: musicLenght.inSeconds.toDouble(),
          onChanged: (value) {
            slide(value);
          },
        ));
  }

  void slide(double sec) {
    Duration newPosition = new Duration(seconds: sec.toInt());
    if (previousWord.contains("\n")) {
      previousWord = "";
    }
    _player.seek(newPosition);
  }

  Future<void> dataHandle(
      String lyrics,
      List<double> arrayTime,
      List<String> arrayWord,
      Map<int, String> timeAndWord,
      Map<int, String> sentences,
      Map<int, int> timeNotSing) async {
    // đọc file xml
    String xmlString = await rootBundle.loadString('assets/data/lyrics.xml');
    lyrics = xmlString;

    // loại bỏ các thành phần không cần thiết.
    var array = lyrics.split('<param s="b">');
    array.removeAt(0);
    for (int i = 0; i < array.length; i++) {
      array[i] = array[i].replaceAll('</param>', '');
      array[i] = array[i].replaceAll('</data>', '');
      array[i] = array[i].trim();

      String paragraph = array[i]; //từng câu trong bài hát
      paragraph = paragraph.replaceAll('<i va="', '');
      paragraph = paragraph.replaceAll('</i>', '');
      paragraph = paragraph.replaceAll('">', ' ');

      List<String> wordByWord = paragraph.split(' ');
      wordByWord.removeWhere((item) => item == "" || item.codeUnits[0] == 13);

      // lưu thời gian tương ứng  với những từ xuất hiện .
      for (int j = 0; j < wordByWord.length; j++) {
        if (j % 2 == 0) {
          var convertDouble = double.parse(wordByWord[j]);
          arrayTime.add(convertDouble);
        } else {
          arrayWord.add(wordByWord[j] + " ");
        }
      }
      // kết thúc một câu.
      arrayWord[arrayWord.length - 1] = arrayWord[arrayWord.length - 1] + "\n";
    }

    var temp = 0;

    String s = "";
    Map<int, String> tempArray = {};
    timeNotSing[0] = (arrayTime[0] * 1000000).toInt();

    //lưu thời gian và từ xuất hiện theo dạng map
    //lưu thời gian xuất hiện theo từng câu vào mảng sentences.
    for (int i = 0; i < arrayTime.length; i++) {
      timeAndWord[(arrayTime[i] * 1000000).toInt()] = arrayWord[i];

      if (!arrayWord[i].contains("\n")) {
        s = s + arrayWord[i];
        tempArray[(arrayTime[i] * 1000000).toInt()] = arrayWord[i];
      } else {
        tempArray[(arrayTime[i] * 1000000).toInt()] = arrayWord[i];
        s = s + arrayWord[i];
        sentences[(arrayTime[temp] * 1000000).toInt()] = s;
        temp = i + 1;
        s = "";

        if (i != arrayTime.length - 1) {
          if (arrayTime[i + 1] - arrayTime[i] > 3) {
            timeNotSing[(arrayTime[i] * 1000000).toInt()] =
                (arrayTime[i + 1] * 1000000).toInt();
          }
        }
      }
    }
    this.arrayTime = arrayTime;
    this.arrayWord = arrayWord;
    this.sentences = sentences;
    this.timeAndWord = timeAndWord;
    this.timeNotSing = timeNotSing;
    checkReadFile = 1;
  }

  _scrollToBottom() {
    _scrollController.jumpTo(_scrollController.position.minScrollExtent);
  }

  Widget lyric() {
    //  xử lí dữ liệu
    if (checkReadFile == 0) {
      dataHandle(this.lyrics, this.arrayTime, this.arrayWord, this.timeAndWord,
          this.sentences, this.timeNotSing);
    }

    this.previousWord = "";
    this.nextWord = "";
    int index = 0;

    // tìm chữ đang hát
    for (int i = 0; i < timeAndWord.keys.length; i++) {
      if (position.inMicroseconds - timeAndWord.keys.elementAt(i) >= -50000 &&
          position.inMicroseconds - timeAndWord.keys.elementAt(i) < 200000) {
        timeOfWord = timeAndWord.keys.elementAt(i);
      }
    }

    // tìm từ đang hát và thời gian của từ đang hát.
    // print(lyricWillSing);
    if (!timeAndWord[timeOfWord].toString().contains("null")) {
      wordIsSinging = timeAndWord[timeOfWord].toString();
    } else {
      wordIsSinging = "";
    }
    // print(timeOfWord);

    print(timeAndWord[timeOfWord]);

    //tìm câu có chữ đang hát
    for (int i = 0; i < sentences.keys.length; i++) {
      if (timeOfWord >= sentences.keys.elementAt(i)) {
        timeStartOfSentences = sentences.keys.elementAt(i);
        // break;
      }
    }

    // print(sentences[timeStartOfSentences]);

    // print(sentences);

    //in câu tiếp theo sẽ hát.
    sentences.forEach((key, value) {
      if (key == timeStartOfSentences) {
        if (index == sentences.length - 1) {
          lyricWillSing = "";
        } else {
          lyricWillSing = sentences.values.elementAt(index + 1);
        }
      }
      index = index + 1;
    });

    // print(wordIsSinging);

    // cắt câu đang hát ở dạng  {những từ trước từ đang hát --- từ đang hát -- những từ sau từ đang hát}
    if (wordIsSinging != "") {
      // print("${timeOfWord}---${wordIsSinging}---${timeStartOfSentences}");
      for (int i = 0; i < arrayTime.length; i++) {
        int timeMicroSecond = (arrayTime[i] * 1000000).toInt();
        if (timeMicroSecond >= timeStartOfSentences &&
            timeMicroSecond < timeOfWord) {
          previousWord = previousWord + arrayWord[i];
          // print(previousWord);
        } else if (timeMicroSecond > timeOfWord) {
          nextWord = nextWord + arrayWord[i];

          if (arrayWord[i].contains("\n")) {
            if (wordIsSinging.contains("\n")) {
              nextWord = "";
            }
            break;
          }
        }
      }
    }
    int timeNoSing = -1;

    for (int i = 0; i < timeNotSing.keys.length; i++) {
      if (position.inMicroseconds > timeNotSing.keys.elementAt(i) &&
          position.inMicroseconds < timeNotSing.values.elementAt(i)) {
        lyricWillSing = "";
        nextWord = "";
        wordIsSinging = "";
        previousWord = "";
        timeNoSing = timeNotSing.keys.elementAt(i);
      }
    }
    print(timeAndWord[timeNoSing]);
    if (timeNoSing != -1 && timeNoSing != 0) {
      index = 0;
      for (int i = 0; i < sentences.keys.length; i++) {
        if (timeNoSing >= sentences.keys.elementAt(i)) {
          timeStartOfSentences = sentences.keys.elementAt(i);
          // break;
        }
      }
      sentences.forEach((key, value) {
        if (key == timeStartOfSentences) {
          print(1);
          if (index == sentences.length - 1) {
            lyricWillSing = "";
          } else {
            previousWord = sentences.values.elementAt(index);
            lyricWillSing = sentences.values.elementAt(index + 1);
          }
        }
        index = index + 1;
      });
      // print(timeStartOfSentences);
    }

    // print(checkReadFile);
    // print(arrayTime.length);

    // print(arrayTime.length);
    // print(timeStartOfSentences);
    // print(timeOfWord);
    // print(previousWord);
    // print(wordIsSinging);
    // print(nextWord);
    // print(lyricIsSinging);
    // print(lyricWillSing);

    // print(timeAndWord);
    String lyricIsSing = previousWord + wordIsSinging + nextWord;
    print(lyricIsSing);
    List<String> listLyric = [lyricIsSing, lyricWillSing];

    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.only(top: 500, bottom: 50, left: 10),
      width: 500,
      height: 60,
      // child: Scaffold(
      //   backgroundColor: Colors.transparent,
      //   body: ListView.builder(
      //       // reverse: true,
      //       itemCount: listLyric.length,
      //       controller: _scrollController,
      //       shrinkWrap: true,
      //       itemBuilder: (context, index) {
      //         // _scrollToBottom();
      //         return ListTile(
      //           title: Text('${listLyric[index]}  ${listLyric[index + 1]}'),
      //           dense: true,
      //         );
      //       }),
      // ),

      child: Column(
        children: <Widget>[
          AnimatedDefaultTextStyle(
            child: Align(
                alignment: Alignment.centerLeft,
                child: Row(children: <Widget>[
                  Text(
                    "${previousWord.replaceAll("\n", '')}",
                    style: TextStyle(
                      color: Colors.red,
                    ),
                  ),
                  Text(
                    "${wordIsSinging.replaceAll("\n", '')}",
                    style: TextStyle(
                      color: Colors.red,
                    ),
                  ),
                  Text(
                    "${nextWord.replaceAll("\n", '')}",
                  ),
                ])),
            style: TextStyle(
              fontSize: 12.0,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            duration: const Duration(milliseconds: 200),
          ),
          AnimatedDefaultTextStyle(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("${lyricWillSing}"),
            ),
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 12.0,
              color: Colors.grey.shade300,
              fontWeight: FontWeight.w100,
            ),
            duration: const Duration(milliseconds: 0),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    // dùng để phát âm thanh của audio files
    _player = new AudioPlayer();

    // sao chép nội dung file vào một thư mục tạm thời trong thiết bị, nơi đó sẽ phát dưới dạng tệp cục bộ
    cache = new AudioCache(fixedPlayer: _player);

    // dùng cache để lấy giá trị và nội dung file audio sau đó _player sẽ đảm nhiệm phần xử lí file ( dừng phát, ....)
    // lấy độ dài time của file mp3
    _player.durationHandler = (lenght) {
      setState(() {
        musicLenght = lenght;
      });
    };

    //sẽ phát âm thanh từ giá trị p trở đi
    _player.positionHandler = (p) {
      setState(() {
        position = p;
      });
    };

    cache.load("nhac.mp3");
    // readFile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
            image: DecorationImage(
          image: AssetImage("assets/anh.png"),
          fit: BoxFit.cover,
        )),
        child: Container(
          child: Column(
            children: [
              // Padding(
              //   // cách top 630 px
              //   padding: const EdgeInsets.only(top: 630),
              // ),
              lyric(),
              // Text("${myText3}"),
              Container(
                  // padding: const EdgeInsets.only(top: 630),
                  child: Row(
                mainAxisSize: MainAxisSize.max,
                //chỉnh các phần tử trong Row vào giữa Row theo chiều ngang
                mainAxisAlignment: MainAxisAlignment.center,
                // chỉnh các phần tử trong Row vào giữa Row theo chiều dọc
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                      "${position.inMinutes}:${position.inSeconds.remainder(60)}"),
                  slider(),
                  Text(
                      "${musicLenght.inMinutes}:${musicLenght.inSeconds.remainder(60)}")
                ],
              )),
              IconButton(
                iconSize: 62.0,
                color: Colors.black,
                onPressed: () {
                  if (!isPlay) {
                    cache.play("nhac.mp3");
                    setState(() {
                      playBtn = Icons.pause;
                      isPlay = true;
                    });
                  } else {
                    _player.pause();
                    setState(() {
                      playBtn = Icons.play_arrow;
                      isPlay = false;
                    });
                  }
                },
                icon: Icon(
                  playBtn,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
