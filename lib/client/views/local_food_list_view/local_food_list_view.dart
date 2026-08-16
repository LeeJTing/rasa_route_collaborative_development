import 'package:flutter/material.dart';

class LocalFoodListView extends StatefulWidget {
  const LocalFoodListView({super.key});

  @override
  State<LocalFoodListView> createState() => _LocalFoodListViewState();
}

class _LocalFoodListViewState extends State<LocalFoodListView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Food List'),
      ),
      body: const Center(
        child: Text('Local Food List'),
      ),
    );
  }
}

