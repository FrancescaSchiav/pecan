#Francesca Schiavello

#Equatios for conversion found at: http://www.uwgb.edu/dutchs/usefuldata/utmformulas.htm

# Finds proper zone
zone = function(long) {
z = abs(-180-(long))%/%6 +1
return(z)
}


#What Lat long do you want? (Degrees will be converted to radians)
projection = function(lat, long){
lat = lat*pi/180
z = zone(long)
long = long*pi/180
central = ((-180 +6*z) - 180 + 6*(z-1))/2
longKnot = central*pi/180 


a = 6378137  #equatorial radius in meters
b = 6356752.3141  #polar radius in meters

#Some symbols
kNot = 0.9996
e = 0.08
ePrime = 0.007 #eccentricity of Earth's elliptical cross section
n = (a-b)/(a+b)
rho = a*(1-(e^2))/((1-(e^2)*sin(lat)^2)^1.5) #radius of curvature of the earth in the meridian plane
nu = a/((1-(e^2)*sin(lat)^2)^0.5) #radius of curvature of the earth perpendicular to the meridian plane
 p = long-longKnot
#p = 0.049

#Calculating the Meridional Arc

# (USGS form)
M = a*((1-((e^2)/4)-(3*(e^4)/64) - (5*(e^6)/256))*lat-((3*(e^2)/8)+(3*(e^4)/32)+(45*(e^6)/1024))*sin(2*lat) + ((15*(e^4)/256)+(45*(e^6)/1024))*sin(4*lat)-(35*(e^6)/3072)*sin(6*lat)) #where lat is in radians

#Converting lat long to UTM
K1 = M*kNot
K2 = kNot*nu*sin(2*lat)/4 
K3 = (kNot*nu*sin(lat)*(cos(lat)^3)/24)*((5-(tan(lat)^2)+9*(ePrime^2)*(cos(lat)^2)+(4*ePrime^4)*(cos(lat)^4)))
K4 = kNot*nu*cos(lat)
K5 = (kNot*nu*(cos(lat)^3)/6)*(1-(tan(lat)^2)+(ePrime^2)*(cos(lat)^2))


#Northing (using USGS form)
y = K1 + K2*p^2 + K3*p^4
#y

#Easting relative to Central Meridian (using USGS form)
x = (K4*p + K5*p^3) + 500000


coords = c(x,y,z)
return(coords)
}

projection2= function(lat, long) {
  
  lat = lat*pi/180
  long = long*pi/180
  f = 1/298.257223563
  n = f/(2-f)
  a = (6378.137/(1+n)) * (1+ (n^2)/4 + (n^4)/64)
  
  t = sinh(atanh(sin(lat)) - (2*sqrt(n) / (1+n) * atanh(sin(lat) * 2 *sqrt(n) / (1+n))))
  e = atan(t/cos(long-longKnot))
  nu = atanh(sin(long-longKnot)/sqrt(1+t^2))
  A1 = n/2 - 2*(n^2)/3 + 5*(n^3)/16
  A2 = 13*(n^2)/48 -3* (n^3)/5
  A3 = 61*(n^3)/240
  B1 = n/2 - 2*(n^2)/3 + 37*(n^3)/96
  B2 = (n^2)/48 + (n^3)/15
  B3 = 17*(n^3)/480
  D1 = 2*n - 2*(n^2)/3 + 2*(n^3)
  D2 = 7*(n^2)/3 - 8*(n^3)/5
  D3 = 56*(n^3)/15
  
  easting = 500 + .9996 * a * (nu + A1*cos(2*e)*sinh(2*nu) + A2*cos(4*e)*sinh(4*nu) + A3*cos(6*e)*sinh(6*nu))
  northing = .9996 * a * (e + A1*sin(2*e)*cosh(2*nu) + A2*sin(4*e)*cosh(4*nu) + A3*sin(6*e)*cosh(6*nu))          
  
  coords = c(easting, northing, z)
  return(coords)
}
