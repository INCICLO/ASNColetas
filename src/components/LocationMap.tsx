import {useEffect} from 'react';
import {CircleMarker,MapContainer,TileLayer,useMap,useMapEvents} from 'react-leaflet';
import {LocateFixed,MapPin} from 'lucide-react';

type Props={data:{lat:number;lng:number};setData:(key:any,value:any)=>void};

function MapController({lat,lng,onPick}:{lat:number;lng:number;onPick:(lat:number,lng:number)=>void}){
  const map=useMap();
  useEffect(()=>{map.setView([lat,lng],Math.max(map.getZoom(),16),{animate:true})},[lat,lng,map]);
  useMapEvents({click:event=>onPick(event.latlng.lat,event.latlng.lng)});
  return <CircleMarker center={[lat,lng]} radius={11} pathOptions={{color:'#fff',weight:4,fillColor:'#eb5b2b',fillOpacity:1}}/>;
}

export function LocationMap({data,setData}:Props){
  const locate=()=>{
    if(!navigator.geolocation)return alert('Este aparelho não oferece localização automática. Marque o ponto diretamente no mapa.');
    navigator.geolocation.getCurrentPosition(
      position=>{setData('lat',position.coords.latitude);setData('lng',position.coords.longitude)},
      ()=>alert('Não foi possível acessar sua localização. Autorize a localização no navegador ou marque o ponto no mapa.'),
      {enableHighAccuracy:true,timeout:15000,maximumAge:30000}
    );
  };
  return <div className="map-block">
    <div className="location-options single"><button onClick={locate}><LocateFixed/>Usar minha localização atual</button></div>
    <div className="map-wrap">
      <MapContainer center={[data.lat,data.lng]} zoom={14} scrollWheelZoom>
        <TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"/>
        <MapController lat={data.lat} lng={data.lng} onPick={(lat,lng)=>{setData('lat',lat);setData('lng',lng)}}/>
      </MapContainer>
      <div className="map-tip"><MapPin/>Clique no mapa para marcar o ponto exato</div>
    </div>
    <div className="coordinates"><span>Coordenadas do ponto selecionado</span><b>{data.lat.toFixed(6)}, {data.lng.toFixed(6)}</b></div>
  </div>;
}
