import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_video_assistant/env/env.dart';
import 'package:flutter_video_assistant/models/message.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_frame_extractor/video_frame_extractor.dart';
import 'package:video_player/video_player.dart';

Future <String> imgsToB64Url(String imgPath) async{
    File imgFile = File(imgPath);
    List<int> imgBytes = await imgFile.readAsBytes();
    String imgB64 = base64Encode(imgBytes);
    String url = "data:image/png;base64," + imgB64;
    return url;
}

Future<List<String>> getVideoFrames(String videoPath) async {
  return await VideoFrameExtractor.fromFile(
    video: File(videoPath),
    imagesCount: 5,
    destinationDirectoryPath: (await getTemporaryDirectory()).path,
    onProgress: (progress) {},
  );
}

Future<String> getAudioTranscript(String audioPath) async {
  final transcription =  await OpenAI.instance.audio.createTranscription(

    file: File(audioPath),
    model: "whisper-1",
    responseFormat: OpenAIAudioResponseFormat.json,
  );

  return transcription.text;
}

Future<String> processVideo(List<Message> history, String videoPath) async {


  final frames = await getVideoFrames(videoPath);
  final b64Frames = await Future.wait(frames.map((frame) => imgsToB64Url(frame)));


  final transcription = await getAudioTranscript(videoPath);


  // the system message that will be sent to the request.
  final systemMessage = OpenAIChatCompletionChoiceMessageModel(
    content: [
      OpenAIChatCompletionChoiceMessageContentItemModel.text(
        """You are a helpful assistant. You are seeing a video and listening to user. You are given the video and the audio as a transcription. Response to the audio with a text message
        
        Previous Conversations:
        ${history.map((message) => message.toHistoryStr()).join('\n')}
        
        Assistant:
        """
      ),
    ],
    role: OpenAIChatMessageRole.assistant,
  );

  final userMessage = OpenAIChatCompletionChoiceMessageModel(
    content: [
      OpenAIChatCompletionChoiceMessageContentItemModel.text(
        transcription
      ),

      //! image url contents are allowed only for models with image support such gpt-4.
      ...b64Frames.map((frame) => OpenAIChatCompletionChoiceMessageContentItemModel.imageUrl(
        frame
      )).toList()

    ],
    role: OpenAIChatMessageRole.user,
  );


  // all messages to be sent.
  final requestMessages = [
    systemMessage,
    userMessage,
  ];

  OpenAIChatCompletionModel chatCompletion = await OpenAI.instance.chat.create(
    model: "gpt-4o",
    seed: 6,
    messages: requestMessages,
    temperature: 0.2,
    maxTokens: 1024,
  );

  return chatCompletion.choices.first.message.content?.first.text ?? 'Failed';
}



class AssistantScreen extends StatefulWidget {
  @override
  _AssistantScreenState createState() => _AssistantScreenState();
}


class _AssistantScreenState extends State<AssistantScreen> {
  CameraController? controller;
  late Future<void> _initializeControllerFuture;
  bool isRecording = false;
  FlutterTts flutterTts = FlutterTts();
  List<Message> history = [];

  bool isProcessing = false;



  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initCamera();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.storage.request();
  }


  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    setState(() {
      controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
      );
      _initializeControllerFuture = controller!.initialize();
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _startVideoRecording() async {
    await flutterTts.stop();
    if (!controller!.value.isInitialized) {
      return;
    }


    try {
      await controller!.startVideoRecording();
      setState(() {
        isRecording = true;
      });
    } on CameraException catch (e) {
      print(e);
    }
  }

  Future<void> _stopVideoRecording() async {
    if (!controller!.value.isRecordingVideo) {
      return;
    }


    setState(() {
      isProcessing = true;
    });
    try {
      final file = await controller!.stopVideoRecording();
      final videoPath = file.path;
      setState(() {
        isRecording = false;
      });
      String result = await processVideo(history, videoPath);
      history.add(Message(user: MessageUser.bot, text: result));
      await _speak(result);
    } on CameraException catch (e) {
      print(e);
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return SizedBox(
                  child: CameraPreview(controller!),
                  height: double.infinity,
                  width: double.infinity,

                );
              } else {
                return Center(child: CircularProgressIndicator());
              }
            },
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: isProcessing ? const Center(child: CircularProgressIndicator(),) : Center(
              child: GestureDetector(
                onLongPressStart: (_) => _startVideoRecording(),
                onLongPressEnd: (_) => _stopVideoRecording(),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: isRecording ? Colors.green : Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
