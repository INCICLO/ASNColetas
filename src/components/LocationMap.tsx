import {useEffect,useState} from 'react';
import {CircleMarker,MapContainer,TileLayer,useMap,useMapEvents} from 'react-leaflet';
import {LocateFixed,MapPin} from 'lucide-react';

type Props={data:{lat:number;lng:number;address?:string;number?:string;neighborhood?:string;cep?:string};setData:(key:any,value:any)=>void};

type ReverseAddress={
  road?:string;pedestrian?:string;footway?:string;path?:string;residential?:string;
  house_number?:string;neighbourhood?:string;suburb?:string;quarter?:string;
  city_district?:string;village?:string;hamlet?:string;town?:string;city?:string;
  municipality?:string;postcode?:string;
};

function formatCep(value=''){
  const digits=value.replace(/\D/g,'').slice(0,8);
  return digits.length>5?`${digits.slice(0,5)}-${digits.slice(5)}`:digits;
}

function MapController({lat,lng,onPick}:{lat:number;lng:number;onPick:(lat:number,lng:number)=>void}){
  const map=useMap();
  useEffect(()=>{map.setView([lat,lng],Math.max(map.getZoom(),16),{animate:true})},[lat,lng,map]);
  useMapEvents({click:event=>onPick(event.latlng.lat,event.latlng.lng)});
  return <CircleMarker center={[lat,lng]} radius={11} pathOptions={{color:'#fff',weight:4,fillColor:'#eb5b2b',fillOpacity:1}}/>;
}

export function LocationMap({data,setData}:Props){
  const [addressStatus,setAddressStatus]=useState<'idle'|'loading'|'found'|'partial'|'error'>('idle');

  const selectPoint=async(lat:number,lng:number)=>{
    setData('lat',lat);
    setData('lng',lng);
    setAddressStatus('loading');
    try{
      const params=new URLSearchParams({format:'jsonv2',lat:String(lat),lon:String(lng),addressdetails:'1','accept-language':'pt-BR'});
      const response=await fetch(`https://nominatim.openstreetmap.org/reverse?${params}`);
      if(!response.ok)throw new Error('Falha ao consultar o endereço');
      const result=await response.json() as {address?:ReverseAddress};
      const address=result.address||{};
      const road=address.road||address.pedestrian||address.footway||address.path||address.residential||'';
      const neighborhood=address.neighbourhood||address.suburb||address.quarter||address.city_district||address.village||address.hamlet||address.town||address.city||address.municipality||'';
      const number=address.house_number||'';
      const cep=formatCep(address.postcode);

      setData('address',road);
      setData('number',number);
      setData('neighborhood',neighborhood);
      setData('cep',cep);
      setAddressStatus(road&&neighborhood&&cep?'found':'partial');
    }catch{
      setAddressStatus('error');
    }
  };

  const locate=()=>{
    if(!navigator.geolocation)return alert('Este aparelho não oferece localização automática. Marque o ponto diretamente no mapa.');
    navigator.geolocation.getCurrentPosition(
      position=>void selectPoint(position.coords.latitude,position.coords.longitude),
      ()=>alert('Não foi possível acessar sua localização. Autorize a localização no navegador ou marque o ponto no mapa.'),
      {enableHighAccuracy:true,timeout:15000,maximumAge:30000}
    );
  };
  return <div className="map-block">
    <div className="location-options single"><button type="button" onClick={locate} disabled={addressStatus==='loading'}><LocateFixed/>{addressStatus==='loading'?'Localizando e buscando endereço...':'Usar minha localização atual'}</button></div>
    <div className="map-wrap">
      <MapContainer center={[data.lat,data.lng]} zoom={14} scrollWheelZoom>
        <TileLayer attribution='&copy; OpenStreetMap' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"/>
        <MapController lat={data.lat} lng={data.lng} onPick={(lat,lng)=>void selectPoint(lat,lng)}/>
      </MapContainer>
      <div className="map-tip"><MapPin/>Clique no mapa para marcar o ponto exato</div>
    </div>
    <div className="coordinates"><span>Coordenadas do ponto selecionado</span><b>{data.lat.toFixed(6)}, {data.lng.toFixed(6)}</b></div>
    <div className={`address-lookup-status ${addressStatus}`} aria-live="polite">
      {addressStatus==='loading'&&'Buscando os dados do endereço...'}
      {addressStatus==='found'&&'Endereço preenchido automaticamente. Confira os dados antes de continuar.'}
      {addressStatus==='partial'&&'Preenchemos os dados encontrados. Complete os campos que ficaram vazios.'}
      {addressStatus==='error'&&'Não foi possível identificar o endereço automaticamente. Você pode preencher os campos abaixo.'}
    </div>
  </div>;
}
