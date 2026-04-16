import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../widgets/add_transaction_sheet.dart';

class AtmMarker {
  final String name;
  final String address;
  final LatLng location;
  final String status;
  final String openingHours;
  final String network;
  
  AtmMarker({
    required this.name, 
    required this.address, 
    required this.location, 
    required this.status,
    required this.openingHours,
    required this.network,
  });
}

class ATMLocatorScreen extends StatefulWidget {
  const ATMLocatorScreen({super.key});

  @override
  State<ATMLocatorScreen> createState() => _ATMLocatorScreenState();
}

class _ATMLocatorScreenState extends State<ATMLocatorScreen> {
  final MapController _mapController = MapController();
  AtmMarker? _selectedAtm;
  List<AtmMarker> _atmLocations = [];
  bool _isLoading = false;
  
  LatLng _currentCenter = const LatLng(1.4827, 103.6558); // Bukit Indah, Johor Bahru
  LatLng? _myLocation; // Tracks user's actual or fetched location
  bool _hasInitialLocation = false;

  @override
  void initState() {
    super.initState();
    _locateAndFetchATMs();
  }

  Future<void> _locateAndFetchATMs() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      LatLng targetLocation;
      
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        targetLocation = _currentCenter;
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GPS Denied. Using fallback location.')));
      } else {
        Position? position;
        try {
          position = await Geolocator.getCurrentPosition(
             desiredAccuracy: LocationAccuracy.high,
             timeLimit: const Duration(seconds: 15),
          );
        } catch (e) {
          position = await Geolocator.getLastKnownPosition();
        }
        
        if (position != null) {
          targetLocation = LatLng(position!.latitude, position!.longitude);
          _hasInitialLocation = true;
          _myLocation = targetLocation; // Save user's location
        } else {
          targetLocation = _currentCenter;
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GPS timeout. Using Bukit Indah fallback.')));
        }
      }
      
      _currentCenter = targetLocation;
      _mapController.move(targetLocation, 14.5);
      
      await _fetchATMsFromOverpass(targetLocation);

    } catch (e) {
       // if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not fetch location. Using fallback.')));
       await _fetchATMsFromOverpass(_currentCenter);
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _fetchATMsFromOverpass(LatLng location) async {
    if (!mounted) return;
    setState(() { _isLoading = true; _selectedAtm = null; });
    
    try {
       // Search for all amenity=atm within a 3000m radius of the map center
       final query = '[out:json];node(around:3000,${location.latitude},${location.longitude})["amenity"="atm"];out;';
       final url = Uri.parse('https://overpass-api.de/api/interpreter');
       
       final response = await http.post(
         url,
         headers: {'Content-Type': 'application/x-www-form-urlencoded'},
         body: 'data=$query',
       );
       
       if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final elements = data['elements'] as List<dynamic>;
          
          List<AtmMarker> newATMs = [];
          for (var e in elements) {
             double lat = e['lat'];
             double lon = e['lon'];
             var tags = e['tags'] ?? {};
             
             String name = tags['name'] ?? tags['operator'] ?? tags['brand'] ?? 'Generic ATM Cashpoint';
             String city = tags['addr:city'] ?? '';
             String street = tags['addr:street'] ?? 'Local Area';
             String addr = city.isEmpty ? street : '$street, $city';
             
             String openingHours = tags['opening_hours'] ?? '24 Hours';
             String network = tags['network'] ?? 'Local Network';
             
             newATMs.add(AtmMarker(
               name: name,
               address: addr,
               location: LatLng(lat, lon),
               status: 'Active', 
               openingHours: openingHours,
               network: network,
             ));
          }
          
          if (mounted) {
             setState(() {
                _atmLocations = newATMs;
             });
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(
               content: Text('Successfully tracked ${newATMs.length} real ATMs via Satellite!'),
               backgroundColor: Colors.green,
               duration: const Duration(seconds: 2),
             ));
          }
       }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network Error fetching ATMs.')));
    } finally {
       if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live ATM Scanner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF19326D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 13.0,
              onTap: (_, __) {
                setState(() { _selectedAtm = null; });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.expensix',
              ),
              MarkerLayer(
                markers: [
                  // 1. Render all ATM Markers
                  ..._atmLocations.map((atm) {
                    final isSelected = _selectedAtm?.name == atm.name && _selectedAtm?.location == atm.location;
                    return Marker(
                      point: atm.location,
                      width: isSelected ? 60 : 45,
                      height: isSelected ? 60 : 45,
                      child: GestureDetector(
                        onTap: () {
                          setState(() { _selectedAtm = atm; });
                          _mapController.move(atm.location, 15.0);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.elasticOut,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? Colors.redAccent : const Color(0xFF19326D),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                            ],
                            border: Border.all(color: Colors.white, width: isSelected ? 3 : 2),
                          ),
                          child: const Icon(Icons.atm, color: Colors.white),
                        ),
                      ),
                    );
                  }),
                  // 2. Render User's Location Marker (Blue Dot)
                  if (_myLocation != null)
                    Marker(
                      point: _myLocation!,
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blueAccent.withValues(alpha: 0.3),
                        ),
                        child: Center(
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blueAccent,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          
          // Search Area Button Overlay
          Positioned(
             top: 16,
             right: 0,
             left: 0,
             child: Center(
               child: AnimatedOpacity(
                 opacity: _isLoading ? 0.0 : 1.0,
                 duration: const Duration(milliseconds: 300),
                 child: ElevatedButton.icon(
                   style: ElevatedButton.styleFrom(
                     backgroundColor: Colors.white,
                     foregroundColor: const Color(0xFF19326D),
                     elevation: 8,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                   ),
                   onPressed: () {
                      final bounds = _mapController.camera.center;
                      _fetchATMsFromOverpass(bounds);
                   },
                   icon: const Icon(Icons.radar),
                   label: const Text('Search This Area', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                 ),
               ),
             ),
          ),
          
          if (_selectedAtm != null && !_isLoading)
             Positioned(
               bottom: 30,
               left: 20,
               right: 20,
               child: _buildAtmDetailsCard(_selectedAtm!),
             ),
             
          // Re-center User Location
          Positioned(
             right: 20,
             bottom: _selectedAtm != null && !_isLoading ? 330 : 30,
             child: FloatingActionButton(
                heroTag: 'my_loc',
                backgroundColor: Colors.white,
                onPressed: () async {
                  if (_hasInitialLocation) {
                     Position? position;
                     try {
                        position = await Geolocator.getCurrentPosition(
                           desiredAccuracy: LocationAccuracy.high, 
                           timeLimit: const Duration(seconds: 15)
                        );
                     } catch (e) {
                        position = await Geolocator.getLastKnownPosition();
                     }
                     if (position != null) {
                       setState(() { 
                         _myLocation = LatLng(position!.latitude, position!.longitude); 
                         _selectedAtm = null; 
                       });
                       _mapController.move(_myLocation!, 14.5);
                     }
                  } else {
                     _locateAndFetchATMs();
                  }
                },
                child: const Icon(Icons.my_location, color: Color(0xFF19326D)),
             ),
          ),

          // Loading Overlay
          if (_isLoading)
            Container(
               color: Colors.black45,
               child: Center(
                  child: Card(
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                     child: const Padding(
                       padding: EdgeInsets.all(32.0),
                       child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF19326D)),
                            SizedBox(height: 24),
                            Text('Scanning Satellite Data...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF19326D)))
                          ]
                       )
                     )
                  )
               )
            )
        ],
      ),
    );
  }

  Widget _buildAtmDetailsCard(AtmMarker atm) {
    String distanceText = '';
    if (_myLocation != null) {
       final int distanceMeters = const Distance().as(LengthUnit.Meter, _myLocation!, atm.location).toInt();
       if (distanceMeters > 999) {
          distanceText = '${(distanceMeters / 1000).toStringAsFixed(1)} KM Away';
       } else {
          distanceText = '${distanceMeters} Meters Away';
       }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(atm.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                Container(
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                   decoration: BoxDecoration(
                     color: Colors.green.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(16),
                   ),
                   child: Text(atm.status, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text(atm.address, style: const TextStyle(color: Colors.grey))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Expanded(child: Text('Hours: ${atm.openingHours}', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500))),
              ],
            ),
            if (distanceText.isNotEmpty) ...[
               const SizedBox(height: 8),
               Row(
                 children: [
                   const Icon(Icons.directions_run, size: 16, color: Colors.blue),
                   const SizedBox(width: 8),
                   Expanded(
                     child: Text(
                       distanceText, 
                       style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 15)
                     )
                   ),
                 ],
               ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.account_balance, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(child: Text('Network: ${atm.network}', style: const TextStyle(color: Colors.black87))),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
               width: double.infinity,
               child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF19326D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('Add Cash Transfer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  onPressed: () async {
                     // Launch AddTransaction sheet right over the map
                     final result = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => const AddTransactionSheet(),
                     );
                     
                     if (result == true && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(
                              content: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Save record successful! 💰', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                              backgroundColor: Colors.green.shade600,
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.only(
                                bottom: MediaQuery.of(context).size.height - 180, // Force it to the Top-Center
                                left: 30, right: 30
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 10,
                           )
                        );
                     }
                  },
               ),
            )
          ],
        ),
      ),
    );
  }
}
