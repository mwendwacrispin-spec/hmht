import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const green = Color(0xff246a49);
const pageColor = Color(0xfff5f7f3);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HomeHuntCameraApp());
}

class HomeHuntCameraApp extends StatelessWidget {
  const HomeHuntCameraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'HomeHunt Camera', debugShowCheckedModeBanner: false, theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: green), scaffoldBackgroundColor: pageColor, useMaterial3: true), home: const PropertyHome());
}

class FieldPhoto {
  const FieldPhoto({required this.id, required this.path, required this.capturedAt, required this.ratio, required this.width, required this.height, this.caption = ''});
  final String id, path, capturedAt, ratio, caption;
  final int width, height;
  Map<String, dynamic> toJson() => {'id':id,'path':path,'capturedAt':capturedAt,'ratio':ratio,'width':width,'height':height,'caption':caption};
  factory FieldPhoto.fromJson(Map<String,dynamic> j) => FieldPhoto(id:j['id'],path:j['path'],capturedAt:j['capturedAt'],ratio:j['ratio']??'Original',width:j['width']??0,height:j['height']??0,caption:j['caption']??'');
}

class FieldProperty {
  FieldProperty({required this.code,required this.name,required this.photos});
  final String code,name;
  final List<FieldPhoto> photos;
  Map<String,dynamic> toJson()=>{'code':code,'name':name,'photos':photos.map((p)=>p.toJson()).toList()};
  factory FieldProperty.fromJson(Map<String,dynamic> j)=>FieldProperty(code:j['code'],name:j['name'],photos:((j['photos'] as List?)??[]).map((p)=>FieldPhoto.fromJson(Map<String,dynamic>.from(p))).toList());
}

class PropertyHome extends StatefulWidget {
  const PropertyHome({super.key});
  @override State<PropertyHome> createState()=>_PropertyHomeState();
}

class _PropertyHomeState extends State<PropertyHome> {
  List<FieldProperty> properties=[];
  String endpoint='http://192.168.43.1:8765',pairingCode='',notice='';
  bool loading=true,sending=false;

  @override void initState(){super.initState();_load();}
  Future<void> _load()async{
    final prefs=await SharedPreferences.getInstance();
    final raw=prefs.getString('homehunt.properties');
    if(raw!=null) properties=(jsonDecode(raw) as List).map((x)=>FieldProperty.fromJson(Map<String,dynamic>.from(x))).toList();
    endpoint=prefs.getString('receiver.url')??endpoint; pairingCode=prefs.getString('receiver.code')??'';
    if(mounted)setState(()=>loading=false);
  }
  Future<void> _save()async{final p=await SharedPreferences.getInstance();await p.setString('homehunt.properties',jsonEncode(properties.map((x)=>x.toJson()).toList()));}
  void _toast(String value)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));

  Future<void> _addProperty()async{
    final code=TextEditingController(),name=TextEditingController();
    final ok=await showModalBottomSheet<bool>(context:context,isScrollControlled:true,backgroundColor:Colors.white,builder:(ctx)=>Padding(padding:EdgeInsets.fromLTRB(20,18,20,MediaQuery.of(ctx).viewInsets.bottom+24),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Add a property',style:TextStyle(fontSize:21,fontWeight:FontWeight.w800)),const SizedBox(height:7),const Text('Enter the exact code shown on the Infinix so the photos match the right property.',style:TextStyle(color:Colors.black54,height:1.45)),const SizedBox(height:16),
      TextField(controller:code,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'HomeHunt property code',hintText:'HH-0001',border:OutlineInputBorder())),const SizedBox(height:10),TextField(controller:name,decoration:const InputDecoration(labelText:'Property name',hintText:'Greenview Apartments',border:OutlineInputBorder())),const SizedBox(height:16),SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save')))
    ])));
    if(ok!=true)return;
    final normalized=code.text.trim().toUpperCase();
    if(!RegExp(r'^[A-Z0-9-]{1,24}$').hasMatch(normalized)||name.text.trim().isEmpty){_toast('Enter a property name and valid code.');return;}
    if(properties.any((p)=>p.code==normalized)){_toast('That code is already on this iPhone.');return;}
    setState(()=>properties.insert(0,FieldProperty(code:normalized,name:name.text.trim(),photos:[])));await _save();
  }

  Future<void> _connection()async{
    final url=TextEditingController(text:endpoint),code=TextEditingController(text:pairingCode);
    final ok=await showModalBottomSheet<bool>(context:context,isScrollControlled:true,backgroundColor:Colors.white,builder:(ctx)=>Padding(padding:EdgeInsets.fromLTRB(20,18,20,MediaQuery.of(ctx).viewInsets.bottom+24),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Connect to your Infinix',style:TextStyle(fontSize:21,fontWeight:FontWeight.w800)),const SizedBox(height:7),const Text('Turn on the Infinix hotspot and start “Receive from iPhone” in HomeHunt. Enter the address and pairing code shown there.',style:TextStyle(color:Colors.black54,height:1.45)),const SizedBox(height:16),
      TextField(controller:url,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'Receiver address',hintText:'http://192.168.43.1:8765',border:OutlineInputBorder())),const SizedBox(height:10),TextField(controller:code,decoration:const InputDecoration(labelText:'Pairing code',border:OutlineInputBorder())),const SizedBox(height:16),SizedBox(width:double.infinity,child:FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save connection')))
    ])));
    if(ok!=true)return;
    endpoint=url.text.trim().replaceAll(RegExp(r'/+$'),'');pairingCode=code.text.trim();
    final prefs=await SharedPreferences.getInstance();await prefs.setString('receiver.url',endpoint);await prefs.setString('receiver.code',pairingCode);if(mounted)setState((){});
  }

  Future<void> _capture(FieldProperty property)async{
    final result=await Navigator.push<FieldPhoto>(context,MaterialPageRoute(builder:(_)=>CameraPage(property:property)));
    if(result==null)return;final index=properties.indexWhere((p)=>p.code==property.code);if(index<0)return;
    setState(()=>properties[index].photos.insert(0,result));await _save();
  }

  Future<void> _send(FieldProperty property)async{
    if(property.photos.isEmpty){_toast('Take at least one photo first.');return;}
    if(pairingCode.isEmpty){await _connection();if(pairingCode.isEmpty)return;}
    setState(()=>sending=true);
    try{
      final archive=Archive(),photoManifest=<Map<String,dynamic>>[];
      for(var i=0;i<property.photos.length;i++){
        final photo=property.photos[i],file=File(property.photos[i].path);if(!await file.exists())continue;
        final name='${(i+1).toString().padLeft(3,'0')}-${_safe(property.name)}.jpg',bytes=await file.readAsBytes();
        archive.addFile(ArchiveFile('photos/$name',bytes.length,bytes));
        photoManifest.add({'id':photo.id,'file':'photos/$name','originalName':name,'category':'General','caption':photo.caption,'aspectRatio':photo.ratio,'capturedAt':photo.capturedAt,'width':photo.width,'height':photo.height,'amenityId':null});
      }
      final manifest={'format':'homehunt-photo-handoff','version':1,'propertyCode':property.code,'propertyName':property.name,'createdAt':DateTime.now().toUtc().toIso8601String(),'photos':photoManifest};
      final jsonBytes=utf8.encode(jsonEncode(manifest));archive.addFile(ArchiveFile('manifest.json',jsonBytes.length,jsonBytes));
      final bytes=ZipEncoder().encode(archive);
      final response=await http.post(Uri.parse('$endpoint/api/photo-handoff'),headers:{'Content-Type':'application/zip','X-HomeHunt-Token':pairingCode,'X-HomeHunt-Property-Code':property.code},body:bytes).timeout(const Duration(seconds:90));
      if(response.statusCode<200||response.statusCode>=300)throw Exception('Infinix replied ${response.statusCode}: ${response.body}');
      final reply=jsonDecode(response.body) as Map<String,dynamic>;
      if(mounted)setState(()=>notice=(reply['importStatus'] as String?)??'${property.code} sent · ${photoManifest.length} photos');
    }catch(e){if(mounted)setState(()=>notice='Send failed. Check hotspot and receiver: $e');}finally{if(mounted)setState(()=>sending=false);}
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(backgroundColor:pageColor,title:const Row(children:[Icon(Icons.home_work_rounded,color:green),SizedBox(width:9),Text('HomeHunt Camera',style:TextStyle(fontWeight:FontWeight.w800))]),actions:[IconButton(onPressed:_connection,icon:const Icon(Icons.wifi_rounded),tooltip:'Infinix connection')]),
    floatingActionButton:FloatingActionButton.extended(onPressed:_addProperty,backgroundColor:green,foregroundColor:Colors.white,icon:const Icon(Icons.add),label:const Text('Add property')),
    body:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.fromLTRB(18,12,18,105),children:[
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xffe9f2eb),borderRadius:BorderRadius.circular(20)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('IPHONE CAMERA COMPANION',style:TextStyle(fontSize:9,letterSpacing:1.2,fontWeight:FontWeight.w800,color:green)),const SizedBox(height:9),const Text('Capture here. Match on your Infinix.',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800)),const SizedBox(height:6),const Text('Photos stay with their property code and send over the Infinix hotspot.',style:TextStyle(fontSize:12,color:Colors.black54,height:1.4)),const SizedBox(height:12),
        Row(children:[const Icon(Icons.wifi,size:16,color:green),const SizedBox(width:6),Expanded(child:Text(pairingCode.isEmpty?'Connect to Infinix to send photos':endpoint,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w600))),TextButton(onPressed:_connection,child:Text(pairingCode.isEmpty?'Connect':'Edit'))])
      ])),
      if(notice.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Text(notice,style:const TextStyle(fontSize:11,color:green))),
      const SizedBox(height:22),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Properties',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800)),Text('${properties.length}',style:const TextStyle(color:Colors.black45))]),const SizedBox(height:10),
      if(properties.isEmpty)_empty()else ...properties.map(_propertyCard),
      if(sending)const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator())),
    ])),
  );

  Widget _propertyCard(FieldProperty p)=>Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(17),border:Border.all(color:const Color(0xffe8ece7))),child:Column(children:[
    Row(children:[Container(width:46,height:46,decoration:BoxDecoration(color:const Color(0xffedf3ee),borderRadius:BorderRadius.circular(13)),child:const Icon(Icons.apartment_rounded,color:green)),const SizedBox(width:11),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(p.name,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13)),const SizedBox(height:3),Text(p.code,style:const TextStyle(fontSize:10,color:Colors.black54))])),Text('${p.photos.length} photos',style:const TextStyle(fontSize:10,color:Colors.black54))]),const SizedBox(height:11),
    Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>_capture(p),icon:const Icon(Icons.photo_camera_outlined,size:17),label:const Text('Take photos'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:()=>_send(p),icon:const Icon(Icons.wifi_tethering_rounded,size:17),label:const Text('Send')))]),
    if(p.photos.isNotEmpty)Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PhotoGallery(property:p,onDelete:(photo)async{setState(()=>p.photos.remove(photo));await _save();}))),icon:const Icon(Icons.grid_view_rounded,size:15),label:const Text('View photos')))
  ]));
  Widget _empty()=>Padding(padding:const EdgeInsets.only(top:42),child:Column(children:[Container(width:58,height:58,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18)),child:const Icon(Icons.add_home_work_outlined,color:green)),const SizedBox(height:12),const Text('Add your first property',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:5),const Text('Use the same code that appears on the Infinix.',style:TextStyle(color:Colors.black54,fontSize:11))]));
}

class CameraPage extends StatefulWidget {
  const CameraPage({super.key,required this.property});final FieldProperty property;
  @override State<CameraPage> createState()=>_CameraPageState();
}
class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? controller;List<CameraDescription> cameras=[];String ratio='4:3',error='';bool grid=true,busy=false;double zoom=1,maxZoom=4;XFile? review;img.Image? processed;final caption=TextEditingController();
  static const ratioValues=<String,double?>{'4:3':4/3,'16:9':16/9,'3:4':3/4,'9:16':9/16,'1:1':1,'Original':null};
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_start();}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);controller?.dispose();caption.dispose();super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(controller==null)return;if(state==AppLifecycleState.inactive)controller?.dispose();else if(state==AppLifecycleState.resumed)_start(controller?.description);}
  Future<void> _start([CameraDescription? prefer])async{try{cameras=await availableCameras();if(cameras.isEmpty){setState(()=>error='No camera found.');return;}final d=prefer??cameras.firstWhere((x)=>x.lensDirection==CameraLensDirection.back,orElse:()=>cameras.first);final c=CameraController(d,ResolutionPreset.max,enableAudio:false,imageFormatGroup:ImageFormatGroup.jpeg);await c.initialize();maxZoom=await c.getMaxZoomLevel();await c.setFlashMode(FlashMode.off);if(mounted)setState(()=>controller=c);}catch(e){if(mounted)setState(()=>error='Camera unavailable: $e');}}
  Future<void> _switch()async{if(cameras.length<2)return;final old=controller?.description;final next=cameras.firstWhere((c)=>c.lensDirection!=old?.lensDirection,orElse:()=>cameras.first);await controller?.dispose();setState(()=>controller=null);await _start(next);}
  Future<void> _flash()async{final c=controller;if(c==null)return;await c.setFlashMode(c.value.flashMode==FlashMode.off?FlashMode.torch:FlashMode.off);setState((){});}
  Future<void> _take()async{final c=controller;if(c==null||!c.value.isInitialized||busy)return;setState(()=>busy=true);try{final shot=await c.takePicture();final data=img.decodeImage(await File(shot.path).readAsBytes());if(data==null)throw Exception('Cannot read the captured image.');final oriented=img.bakeOrientation(data),target=ratioValues[ratio];setState((){review=shot;processed=target==null?oriented:_crop(oriented,target);caption.clear();});}catch(e){setState(()=>error='$e');}finally{if(mounted)setState(()=>busy=false);}}
  img.Image _crop(img.Image input,double target){final current=input.width/input.height;if((current-target).abs()<0.002)return input;if(current>target){final w=(input.height*target).round();return img.copyCrop(input,x:(input.width-w)~/2,y:0,width:w,height:input.height);}final h=(input.width/target).round();return img.copyCrop(input,x:0,y:(input.height-h)~/2,width:input.width,height:h);}
  Future<void> _save()async{final image=processed;if(image==null)return;final docs=await getApplicationDocumentsDirectory(),code=widget.property.code.replaceAll(RegExp(r'[^A-Z0-9-]'),'_'),folder=Directory('${docs.path}/HomeHunt/Properties/$code');await folder.create(recursive:true);final ix=widget.property.photos.length+1,file=File('${folder.path}/$code-${DateTime.now().millisecondsSinceEpoch}-$ix.jpg');await file.writeAsBytes(img.encodeJpg(image,quality:94),flush:true);Navigator.pop(context,FieldPhoto(id:'${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(10000)}',path:file.path,capturedAt:DateTime.now().toUtc().toIso8601String(),ratio:ratio,width:image.width,height:image.height,caption:caption.text.trim()));}
  @override Widget build(BuildContext context){final c=controller;return Scaffold(backgroundColor:Colors.black,body:SafeArea(child:Stack(fit:StackFit.expand,children:[
    if(review!=null&&processed!=null)Center(child:AspectRatio(aspectRatio:processed!.width/processed!.height,child:Image.file(File(review!.path),fit:BoxFit.cover)))else if(c!=null&&c.value.isInitialized)_cameraPreview(c)else Center(child:Text(error.isEmpty?'Opening camera…':error,style:const TextStyle(color:Colors.white))),
    if(review==null)...[
      Positioned(top:7,left:10,right:10,child:Row(children:[IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close,color:Colors.white)),Expanded(child:Text('${widget.property.code} · ${widget.property.name}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700))),IconButton(onPressed:_flash,icon:Icon(c?.value.flashMode==FlashMode.torch?Icons.flash_on:Icons.flash_off,color:Colors.white)),IconButton(onPressed:_switch,icon:const Icon(Icons.flip_camera_ios,color:Colors.white))])),
      Positioned(top:58,left:10,right:10,height:44,child:ListView(scrollDirection:Axis.horizontal,children:ratioValues.keys.map((key)=>Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(key),selected:ratio==key,onSelected:(_)=>setState(()=>ratio=key)))).toList())),
      if(grid)const Positioned.fill(child:IgnorePointer(child:CustomPaint(painter:ThirdsGrid()))),
      if(c!=null&&maxZoom>1)Positioned(left:32,right:32,bottom:108,child:Row(children:[const Icon(Icons.zoom_out,color:Colors.white),Expanded(child:Slider(value:zoom,min:1,max:maxZoom,onChanged:(v){setState(()=>zoom=v);c.setZoomLevel(v);},activeColor:Colors.white)),const Icon(Icons.zoom_in,color:Colors.white)])),
      Positioned(bottom:18,left:18,right:18,child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[_last(),IconButton(onPressed:()=>setState(()=>grid=!grid),icon:Icon(grid?Icons.grid_on:Icons.grid_off,color:Colors.white)),GestureDetector(onTap:_take,child:Container(width:68,height:68,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:Colors.white,width:4)),child:Center(child:Container(width:52,height:52,decoration:const BoxDecoration(color:Colors.white,shape:BoxShape.circle))))),const SizedBox(width:42)])),
    ]else Positioned(left:16,right:16,bottom:18,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:caption,style:const TextStyle(color:Colors.white),decoration:const InputDecoration(labelText:'Caption (optional)',labelStyle:TextStyle(color:Colors.white70),enabledBorder:UnderlineInputBorder(borderSide:BorderSide(color:Colors.white70)))),const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>setState(()=>review=null),icon:const Icon(Icons.refresh),label:const Text('Retake'),style:OutlinedButton.styleFrom(foregroundColor:Colors.white,side:const BorderSide(color:Colors.white70)))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>setState((){review=null;processed=null;}),icon:const Icon(Icons.delete_outline),label:const Text('Delete'),style:OutlinedButton.styleFrom(foregroundColor:Colors.white,side:const BorderSide(color:Colors.white70)))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:_save,icon:const Icon(Icons.check),label:const Text('Save')))]),const SizedBox(height:7),Text('$ratio · ${processed!.width} × ${processed!.height}',style:const TextStyle(color:Colors.white70,fontSize:11))])),
      if(busy)const Positioned.fill(child:ColoredBox(color:Color(0x55000000),child:Center(child:CircularProgressIndicator(color:Colors.white))))
  ])));}
  Widget _cameraPreview(CameraController c)=>Center(child:AspectRatio(aspectRatio:ratioValues[ratio]??c.value.aspectRatio,child:ClipRect(child:FittedBox(fit:BoxFit.cover,child:SizedBox(width:c.value.previewSize!.height,height:c.value.previewSize!.width,child:CameraPreview(c))))));
  Widget _last()=>widget.property.photos.isEmpty?const SizedBox(width:42):ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.file(File(widget.property.photos.first.path),width:42,height:42,fit:BoxFit.cover));
}

class ThirdsGrid extends CustomPainter {
  const ThirdsGrid();
  @override void paint(Canvas canvas,Size size){final p=Paint()..color=Colors.white38..strokeWidth=.7;for(var i=1;i<3;i++){final x=size.width*i/3,y=size.height*i/3;canvas.drawLine(Offset(x,0),Offset(x,size.height),p);canvas.drawLine(Offset(0,y),Offset(size.width,y),p);}}
  @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}

class PhotoGallery extends StatelessWidget {
  const PhotoGallery({super.key,required this.property,required this.onDelete});final FieldProperty property;final Future<void> Function(FieldPhoto) onDelete;
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('${property.code} · Photos')),body:GridView.builder(padding:const EdgeInsets.all(10),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,crossAxisSpacing:8,mainAxisSpacing:8),itemCount:property.photos.length,itemBuilder:(context,index){final p=property.photos[index];return GestureDetector(onTap:()=>showDialog(context:context,builder:(ctx)=>Dialog(child:Column(mainAxisSize:MainAxisSize.min,children:[Image.file(File(p.path)),Padding(padding:const EdgeInsets.all(10),child:Text(p.caption.isEmpty?'${p.ratio} · ${p.width} × ${p.height}':p.caption)),TextButton.icon(onPressed:()async{await onDelete(p);Navigator.pop(ctx);},icon:const Icon(Icons.delete_outline),label:const Text('Delete photo'))]))),child:ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.file(File(p.path),fit:BoxFit.cover)));}));
}

String _safe(String value)=>value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'),'-').replaceAll(RegExp('-+'),'-').replaceAll(RegExp(r'^-|-$'),'').ifEmpty('property');
extension _StringFallback on String {String ifEmpty(String fallback)=>isEmpty?fallback:this;}
