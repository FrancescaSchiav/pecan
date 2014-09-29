#Francesca Schiavello

#Equatios for conversion found at: http://www.uwgb.edu/dutchs/usefuldata/utmformulas.htm


#What Lat long do you want? (Degrees will be converted to radians)
lat = 35.9898*pi/180
long = -174.4151*pi/180
longKnot = -107*pi/180 # meridian of zone, 60 would be atlantic


a = 6378137  #equatorial radius in meters
b = 6356752.3142  #polar radius in meters

#Some symbols
kNot = 0.9996
e = 0.08
ePrime = 0.007  #eccentricity of Earth's elliptical cross section
rho = a*(1-(e^2))/((1-(e^2)*sin(lat)^2)^1.5) #radius of curvature of the earth in the meridian plane
rho
nu = a/((1-(e^2)*sin(lat)^2)^0.5) #radius of curvature of the earth perpendicular to the meridian plane
nu
p = long-longKnot
p

#Calculating the Meridional Arc
M = a*((1-((e^2)/4)-(3*(e^4)/64) - (5*(e^6)/256))*lat-((3*(e^2)/8)+(3*(e^4)/32)+(45*(e^6)/1024))*sin(2*lat)+((15*(e^4)/256)+(45*(e^6)/1024))*sin(4*lat)-(35*(e^6)/3072)*sin(6*lat)) #where lat is in radians
M

#Converting lat long to UTM
K1 = M*kNot
K1
K2 = kNot*nu*sin(2*lat)/4 
K2
K3 = (kNot*nu*sin(lat)*(cos(lat)^3)/24)*((5-(tan(lat)^2)+9*(ePrime^2)*(cos(lat)^2)+(4*ePrime^4)*(cos(lat)^4)))
K3
K4 = kNot*nu*cos(lat)
K4
K5 = (kNot*nu*(cos(lat)^3)/6)*(1-(tan(lat)^2)+(ePrime^2)*(cos(lat)^2))
K5


#Northing
y = K1 + K2*p^2 + K3*p^4
y

#Easting relative to Central Meridian
x = K4*p + K5*p^3
x

     