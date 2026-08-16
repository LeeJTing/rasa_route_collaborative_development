import 'package:flutter/material.dart';

class FoodRecognitionView extends StatefulWidget {
  const FoodRecognitionView({super.key});

  @override
  State<FoodRecognitionView> createState() => _FoodRecognitionViewState();
}

class _FoodRecognitionViewState extends State<FoodRecognitionView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Recognition'),
      ),
      body: const Center(
        child: Text('Food Recognition'),
      ),
    );
  }
}

