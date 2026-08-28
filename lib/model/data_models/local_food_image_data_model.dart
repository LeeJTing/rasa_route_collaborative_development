import '../../core/json_model.dart';

/// Wire shape of one row in `public.local_food_image`.
class LocalFoodImageDataModel implements JsonModel {
  const LocalFoodImageDataModel({
    required this.localFoodImageId,
    required this.imageName,
    required this.localFoodId,
  });

  final int localFoodImageId;
  final String imageName;
  final int localFoodId;

  factory LocalFoodImageDataModel.fromJson(Map<String, dynamic> json) =>
      LocalFoodImageDataModel(
        localFoodImageId: JsonReader.asInt(json['local_food_image_id']),
        imageName: JsonReader.asString(json['img_name']),
        localFoodId: JsonReader.asInt(json['local_food_id']),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'local_food_image_id': localFoodImageId,
    'img_name': imageName,
    'local_food_id': localFoodId,
  };
}
