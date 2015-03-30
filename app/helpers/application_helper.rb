require 'orchestrate'
require 'httparty'
require 'json'
require 'forecast_io'

module ApplicationHelper

  class OrchestrateDatabase
    
    ORC_API_KEY = "f72b43bb-175a-49ea-826e-dded02aa73f6";
    FORECAST_IO_API_KEY = '0fecf5693b3a3c4e8849287ad39aac41';
    WEATHER_UPDATE_INTERVAL = 3600; # 1 hour
    
    # REQUIRE: geoInfo              : a hash map containing geoInfo of a particular address (based on google)
    # EFFECT : return the weather data of the given address if the addres belongs to a particular city in 
    #          either the United States or Canada
    #          - return nil if the address is invalid (i.e. does not belong to any US or Canadian city or cannot 
    #            be recognized by google geocoder)
    def self.getCityWeatherData ( geoInfo )
      if ( Geocoder.isValidAddress( geoInfo ) )    
        cityNameKey = Geocoder.getCityNameKey( geoInfo );    
      else
        return nil;
      end
      result = queryOrchestrate( :cityweather, cityNameKey.to_s ).body;
      time_sin_last_update = Time.now.to_i - result["last_update_time"].to_i;
      if ( time_sin_last_update > WEATHER_UPDATE_INTERVAL )
        updateWeatherData( geoInfo ); 
        result = getCityWeatherData( geoInfo );
      end
      rescue Orchestrate::API::NotFound;
        puts "getCityWeatherData: Key not found in Orchestrate.io"; #TODO
        updateWeatherData( geoInfo );
        result = getCityWeatherData( geoInfo );
      else
        return result;
    end
    
    # REQUIRE: geoInfoArray         : an array of hash maps containing geoInfo for a list of valid city locations
    # EFFECT : return a hash map of weather data for the given list of cities with the cityNameKey as key
    #          - if the geoInfoArray is an empty array, return nil
    def self.getCitiesWeatherData ( geoInfoArray )
      if ( geoInfoArray == nil )
        return nil;
      end
      citiesWeatherData = Hash.new;
      geoInfoArray.each { |geoInfo|
        key = Geocoder.getCityNameKey( geoInfo );
        citiesWeatherData[key] = getCityWeatherData( geoInfo );
      }
      return citiesWeatherData;
    end
    
    # REQUIRE: cityNameKey          : a valid cityNameKey of the form '[city Long Name]_[country code]', e.g. Vancouver_CA
    # EFFECT : return the city weather data of the given city. 
    #          - There is no type checking performed, user of this method must be sure that the cityNameKey supplied is valid
    #          - However, if the cityNameKey was originally generated by Geocoder.getCityNameKey method, the cityNameKey can 
    #            safely be assumed to be valid
    def self.getCityWeatherDataByKey( cityNameKey )
      geoInfo = getGeoInfoByKey( cityNameKey );
      return getCityWeatherData( geoInfo );
    end
    
    # REQUIRE: cityNameKeyArray      : a valid array of cityNameKeys
    # EFFECT : return a hash map of weather data for the given list of cities with the cityNameKey as key
    #          - There is no type checking performed, user of this method must be sure that the cityNameKey supplied is valid
    #          - However, if the cityNameKey was originally generated by Geocoder.getCityNameKey method, the cityNameKey can 
    #            safely be assumed to be valid
    def self.getCitiesWeatherDataByKey( cityNameKeyArray )
      citiesWeatherData = Hash.new;
      cityNameKeyArray.each { |cityNameKey|
        geoInfo = getGeoInfoByKey( cityNameKey );
        key = Geocoder.getCityNameKey( geoInfo );
        citiesWeatherData[key] = getCityWeatherData( geoInfo );
      }
      return citiesWeatherData;
    end
    
    # REQUIRE: geoInfo              : a hash map containing geoInfo of a particular address (based on google)
    # EFFECT : Update the current weather data stored in Orchestrate.io
    #          NOTE: Generally, there is no need to call this method. getCityWeatherData and getCitiesWeatherData
    #                automatically update weather data in Orchestrate.io if the weather data requested is over an
    #                hour old in Orchestrate.io
    def self.updateWeatherData ( geoInfo )      
      latLon = Geocoder.getLatLon( geoInfo );
      updateOrchestrate( :cityweather, Geocoder.getCityNameKey( geoInfo ), queryForecastIO( latLon ) );
    end
    
    # REQUIRE: latLon               : a latitude and longitude pair
    # EFFECT : return a hash map containing the forecast data from Forecast.io
    def self.queryForecastIO ( latLon )
      lat = latLon[:lat];
      lon = latLon[:lng];      
      puts "querying forecast.io"; #TODO     
      ForecastIO.api_key = FORECAST_IO_API_KEY;
      forecast = ForecastIO.forecast( lat.to_i, lon.to_i );
      forecast_hash = Hash.new; 
      forecast_hash[:last_update_time] = Time.now.to_i;
      forecast_hash[:latLon] = latLon;
      forecast_hash[:currently] = forecast.currently;
      forecast_hash[:hourly] = forecast.hourly;
      forecast_hash[:daily_this_week] = forecast.daily;      
      return JSON.parse( forecast_hash.to_json, :symbolize_names => true );          
    end
    
    # REQUIRE: user_id              : A valid google user id that is already stored in Orchestrate.io
    # EFFECT : Retrieve the hash map google user information from Orchestrate.io with the user id as the key
    #           - Return nil if the key cannot be found
    def self.getGoogleUserInfo ( user_id )
      response = queryOrchestrate( :googleuser, user_id.to_s ).body;
    rescue Orchestrate::API::NotFound;
      return nil;
    else      
      return response;
    end
    
    # REQUIRE: user_info            : A hash map containing google user information
    #          user_id              : A valid google user id
    # EFFECT : Store the user information to Orchestrate.io with the user id as the key
    def self.storeGoogleUser ( user_info, user_id )
      client = Orchestrate::Client.new( ORC_API_KEY );
      client.put( :googleuser, user_id, user_info );
    end
    
    # REQUIRE: cityNameKey          : a city name key in the form '[city name]_[country code]' e.g. Vancouver_CA
    # EFFECT : return the geoInfo corresponding to the said cityNameKey
    def self.getGeoInfoByKey( cityNameKey )
      response = queryOrchestrate( :citygeoinfo, cityNameKey.to_s ); 
      if ( isValidOrchestrateResponse( JSON.parse( response.to_json ) ) )
        result = JSON.parse( response.to_json, :symbolize_names => true )[:body][:geoInfo];
      else
        return nil;
      end
      rescue Orchestrate::API::NotFound;
        puts "getGeoInfoByKey: cityNameKey not found in Orchestrate.io"; #TODO
        geoInfo = Geocoder.getGeoInfo( cityNameKey );
        if ( Geocoder.isValidAddress( geoInfo ) )
          updateGeoInfo( geoInfo );
          return geoInfo;
        else
          return nil;
        end
      else
        return result;
    end 
    
    # REQUIRE: geoInfo        : A geoInfo hash map of a particular Canadian or US city
    # EFFECT : store/update the Orchestrate.io database with the said geoInfo Hash 
    def self.updateGeoInfo( geoInfo )
      if ( Geocoder.isValidAddress( geoInfo ) )
        cityNameKey = Geocoder.getCityNameKey( geoInfo );
        geoInfoData = Hash.new;
        geoInfoData[:geoInfo] = geoInfo;
        updateOrchestrate( :citygeoinfo, cityNameKey, geoInfoData );
      end
    end
    
    def self.geoInfoSearchByKey( cityNameKey, cityCount, searchDistance )
      client = Orchestrate::Client.new( ORC_API_KEY );
      geoInfo = getGeoInfoByKey( cityNameKey );
      latLon = Geocoder.getLatLon( geoInfo );
      query = "value.geoInfo.geometry.location:NEAR:{lat:" + latLon[:lat].to_s + " lng:" + latLon[:lng].to_s + " dist:" + searchDistance.to_s + "km}";
      puts "Geo searching through Orchestrate.io: " + query;
      
      response = client.search( :citygeoinfo, query, { limit: 100 } ).body["results"];
      geoInfoArray = Array.new;
      response.each{ |record|
        geoInfoArray << record["value"]["geoInfo"]        
      }
      if ( geoInfoArray.length < (cityCount * 0.70).to_i )
        puts geoInfoArray.length.to_s + " record(s) of geoInfos found,"
        puts "Not encough result found from Orchestrate.io, generating new geoInfos"
        latLons = Geocoder.getSurroundingLatLons( geoInfo, cityCount, 0.5 );
        geoInfoArray = Geocoder.getCitiesGeoInfo( latLons );
      end
      return JSON.parse( geoInfoArray.to_json, :symbolize_names => true );
    end
    
    ######################################################
    # Helper
    ######################################################
    
    # REQUIRE: response             : a json response from Orchestrate.io
    # EFFECT : return true if the orchestrate response contains a body 
    def self.isValidOrchestrateResponse( response ) 
      return response.has_key?("body");
    end
    
    def self.queryOrchestrate( collection, key ) 
      client = Orchestrate::Client.new( ORC_API_KEY );
      puts "Querying Orchestrate: " + collection.to_s + ", " + key.to_s; #TODO
      response = client.get( collection, key ); 
      return response;
    end
    
    def self.updateOrchestrate( collection, key, value ) 
      client = Orchestrate::Client.new( ORC_API_KEY );
      puts "Updating Orchestrate: " + collection.to_s + ", " + key.to_s; #TODO
      response = client.put( collection, key, value ); 
      return response;
    end


    def self.storeFacebookUser ( uid, name )
      client = Orchestrate::Client.new(ORC_API_KEY);
      client.put( :facebookuser, uid, name);
    end

    def self.getFacebookUser ( uid )
      client = Orchestrate::Client.new(ORC_API_KEY);
      response = client.get( :facebookuser, uid.to_s );
    rescue Orchestrate::API::NotFound;
      return nil;
    else      
      return JSON.parse( response.to_json )["body"];
    end
  end
  
  class Geocoder
    
    GOOGLE_URL = 'https://maps.googleapis.com/maps/api/geocode/json?';
    GGEOCODE_API_KEY = "AIzaSyCOvnSbUGSJfQFEZfAHk7zgpP83f9QJrp8";
    
    # REQUIRE: address            : a string address
    # EFFECT : return a geoInfo hash map based on google geocoder
    #          - if google geocoder return no result, return nil
    def self.getGeoInfo( address )
      g_geocode_url = GOOGLE_URL + 'address=' + address.to_s.gsub(/\s/,'+') + '&key=' + GGEOCODE_API_KEY;
      puts "Querying google geocoder at: " + g_geocode_url;
      response = JSON.parse( HTTParty.get( g_geocode_url.to_s ).to_json, :symbolize_names => true )[:results];
      if ( response == [] )
        return nil;
      else
        return response;
      end      
    end
    
    # REQUIRE: A valid geoInfo Hash Map (i.e. a city address belonging to a Canadian or US City)
    # EFFECT : return a hash map { :lat => [...], :lng => [...]}
    def self.getLatLon ( geoInfo )
      if ( isValidAddress( geoInfo ) )
        return geoInfo[0][:geometry][:location];
      else
        return nil;
      end
    end
    
    # REQUIRE: An array of valid geoInfo Hash Maps
    # EFFECT : return an array of latitude and longitude pair hash map
    def self.getLatLonArray ( geoInfoArray )
      latLonArray = Array.new;
      geoInfoArray.each{ |geoInfo|
          latLonArray << geoInfo[0][:geometry][:location];
      }
      return latLonArray;
    end
    
    # REQUIRE: geoInfo            : a geoInfo of a particular central city 
    #          count              : number of latitude and longitude pairs to be returned 
    #          degree             : latitude and longitude offset from the central city by degree
    # EFFECT : An array of latitude and longitude hash maps that surround the given address location
    #          - return nil if the given geoInfo is an invalid address
    def self.getSurroundingLatLons( geoInfo, count, degree )
      if ( !( isValidAddress( geoInfo) ) || geoInfo == nil || count == nil )
        return nil;
      end
      centralLatLon = getLatLon( geoInfo );
      latLonArray = Array.new;
      latLonArray << centralLatLon;
      return generateLatLons( latLonArray, count, degree );
    end
    
    # REQUIRE: latLonArray        : an array of latitude and longitude ( paired as hash element )
    #          count              : number of latitude and longitude pairs to be returned
    # EFFECT : return an array of distinct latitude and longitude pair hash maps through recursive call until
    #          the size of the return latLonArray reaches the count specified 
    def self.generateLatLons ( latLonArray, count, degree )
      puts "Generating latitude and longitude pairs..." #TODO
      latLonArray.each { |latLon|
        tempArr = [ 
          shiftLatLon( latLon,  degree,  0.0 ), 
          shiftLatLon( latLon, -1*degree,  0.0 ), 
          shiftLatLon( latLon,  0.0,  degree ), 
          shiftLatLon( latLon,  0.0, -1*degree ) ];
        
        tempArr.each { |shiftedLatLon|
          if ( latLonArray.length >= count )
            return latLonArray;
          end
          if ( !( latLonArray.include?( shiftedLatLon ) ) )
            latLonArray << shiftedLatLon;
          end
        }    
      }
    end
    
    # REQUIRE: latLon             : a latitude and longitude pair hash map to be shifted
    #          latShift           : latitude offset
    #          lonShift           : longitude offset
    # EFFECT : return a latitude and longitude pair hash map that is shifted based on the provided offset
    #          - there is no need to concern with shifting latitude or longitude off 90 degree or 180 degree
    #            respectively. this function takes care of that.
    def self.shiftLatLon ( latLon, latShift, lonShift )
      lat = latLon[:lat];
      lon = latLon[:lng];
      
      shiftedLat = (lat + latShift);    
      if ( shiftedLat > 90.0 )
        shiftedLat = 180.0 - shiftedLat;
        if ( lon > 0 )
          lon = lon - 180;
        else
          lon = lon + 180;
        end
      elsif ( shiftedLat < -90.0 )
        shiftedLat = -180.0 - shiftedLat;
        if ( lon > 0 )
          lon = lon - 180;
        else
          lon = lon + 180;
        end
      end
      
      shiftedLon = (lon + lonShift);    
      if ( shiftedLon > 180.0 )
        shiftedLon = shiftedLon - 180.0;
      elsif ( shiftedLon < -180.0 )
        shiftedLon = shiftedLon + 180.0; 
      end
      
      shiftedLatLon = Hash.new;
      shiftedLatLon[:lat] = shiftedLat;
      shiftedLatLon[:lng] = shiftedLon;
      return shiftedLatLon;
    end
    
    # REQUIRE: latLon             : a latitude and longitude pair hash map
    # EFFECT : return the geoInfo of the location using google reverse geocoding API
    #          - return nil if google reverse geocoding API return no result
    def self.getReverseGeoInfo( latLon )
      lat = latLon[:lat];
      lon = latLon[:lng];
      g_geocode_url = GOOGLE_URL + 'latlng=' + lat.to_s + ',' + lon.to_s + '&key=' + GGEOCODE_API_KEY;
      response = JSON.parse( HTTParty.get( g_geocode_url.to_s ).to_json, :symbolize_names => true )[:results];
      if ( response == [] )
        return nil;
      else
        return response;
      end      
    end
    
    # REQUIRE: geoInfo            : a geoInfo hash map
    # EFFECT : return true if the geoInfo belongs to a particular Canadian or US city
    def self.isValidAddress ( geoInfo )
      
      if ( geoInfo == [] || geoInfo == nil )
        return false;
      end
      if ( !( geoInfo[0].has_key?(:address_components) ) )
        return false;
      end
      addr_compon_arr = geoInfo[0][:address_components];
      addr_types = Array.new;
      addr_compon_arr.each { |component|
        addr_types << component[:types][0];
        if ( component[:types][0] == "country" && component[:long_name] != "Canada" && component[:long_name] != "United States" )
          return false;
        end
      }
      if ( addr_types.include?("locality") && addr_types.include?("country") )
        return true;
      end
      return false;
    end
    
    # REQUIRE: geoInfo            : a valid geoInfo (a valid address belonging to a Canadian or US city)
    # EFFECT : return the unique city name key for each city e.g. Vancouver is Vancouver_CA
    def self.getCityNameKey ( geoInfo )
      addr_compon_arr = geoInfo[0][:address_components];
      city = "";
      country = "";
      addr_compon_arr.each { |component|
        if ( component[:types][0] == "locality" )
          city = component[:long_name];
        end
        if ( component[:types][0] == "country")
          country = component[:short_name];
        end
      }
      return city + "_" + country;
    end
    
    # REQUIRE: latLonArray        : an array of latitude and longitude hash map
    # EFFECT : return an array of geoInfo based on google geocoder API 
    #          - if any geoInfo relongs to the same Canadian or US city or is invalid, they will be removed
    def self.getCitiesGeoInfo( latLonArray )
      if ( latLonArray == nil )
        return nil;
      end
      geoInfoArray = Array.new;
      latLonArray.each { |latLon|
        sleep 0.2;
        geoInfoArray << getReverseGeoInfo( latLon );
      }
      return removeDuplicateGeoInfos( geoInfoArray );
    end
    
    # REQUIRE: geoInfoArray       : an array of geoInfos, possibly containing duplicates (e.g. belonging to 
    #                               the same Canadian or US city) or invalid address
    # EFFECT : return an array of geoInfo containing no duplicates and no invalid address
    def self.removeDuplicateGeoInfos( geoInfoArray )
      noDuplicateArray = Array.new; 
      cityKeyArray = Array.new;
      geoInfoArray.each { |geoInfo|
        if ( isValidAddress( geoInfo ) )
          cityNameKey = getCityNameKey( geoInfo );
          if !( cityKeyArray.include? cityNameKey )
            OrchestrateDatabase.updateGeoInfo( geoInfo );
            noDuplicateArray << geoInfo;
            cityKeyArray << cityNameKey;
          end
        end
      }
      return noDuplicateArray;
    end
    
  end
  
end