#!/bin/bash
#================ Function to check the status of the last executed command
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "\e[1;41mError: $1\e[0m"
        exit 1
    fi
}

#=============Preliminaries & Initialise OPAM and build bare switch (=compiler)=======
# Get the username of the current user
echo -e "Hello,\e[1;32m $USER\e[0m! Let's get started with \e[1;42m  VinylStation Installation  \e[0m"
#========FFMpeg and fdkaac compilation works with 64bit Bullseye distrib============
echo -e "\e[1;42mUpdate system and install prerequisites\e[0m"
sudo apt-get update && sudo apt-get -y upgrade
check_status "System update and upgrade failed."
sudo apt-get -y install icecast2 nginx libnginx-mod-rtmp pulseaudio mercurial git darcs bubblewrap screen build-essential libvorbis-dev libmp3lame-dev libasound2-dev libgtk-3-dev libssl-dev libasound2-plugins
check_status "Install prerequisites failed."
echo -e "\e[1;42mUpdate system and install prerequisites\e[0m :\e[1;32m Success \e[0m"
#========Get rid of every audio device except the USB interface=========
sudo sed -i '/^dtparam=audio=on$/c\dtparam=audio=off' /boot/firmware/config.txt
check_status "Disable internal audio devices failed."
sudo sed -i '/^dtoverlay=vc4-kms-v3d$/c\#dtoverlay=vc4-kms-v3d' /boot/firmware/config.txt
check_status "Disable internal audio devices failed."
sudo sed -i '/^max_framebuffers=2$/c\#max_framebuffers=2' /boot/firmware/config.txt
echo -e "\e[1;41mGet rid of every audio device except the USB interface\e[0m :\e[1;32m Success \e[0m"
#===============Daemonise Pulseaudio and have it spawn automatically upon system start
sudo sed -i '/^; daemonize = no$/c\daemonize = yes' /etc/pulse/daemon.conf
sudo sed -i '/^; autospawn = yes$/c\autospawn = yes' /etc/pulse/client.conf
echo -e "\e[1;42mDaemonise Pulseaudio and have it spawn automatically upon system start \e[0m :\e[1;32m Success \e[0m"
#===============Get OPAM and prepare switch
echo -e "\e[1;42mGet OPAM and prepare switch\e[0m"
bash -c "sh <(curl -fsSL https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh)"
check_status "Install OPAM failed."
opam init -y --bare --shell-setup --disable-sandboxing 
#opam switch create liquidsoap ocaml-base-compiler.4.14.2 -y #This line works on RasPi3+
opam switch create liquidsoap ocaml-base-compiler.5.3.0 -y

check_status "Create OPAM switch failed."
eval "$(opam env --switch=liquidsoap)"
#export IS_SNAPSHOT=false;
echo -e "\e[1;42mGet OPAM and prepare switch \e[0m : \e[1;32mSuccess\e[0m"
#===============Create and prepare relevant directories and permissions
sudo mkdir /etc/liquidsoap;
sudo mkdir /etc/liquidsoap/hls;
sudo mkdir /etc/liquidsoap/hls/persist
sudo touch /etc/liquidsoap/vinylfromWax.liq;
sudo chmod 666 /etc/liquidsoap/vinylfromWax.liq;
sudo mkdir /var/log/liquidsoap;
sudo touch /var/log/liquidsoap/VinylfromWax.log;
sudo chmod 777 /var/log/liquidsoap/VinylfromWax.log;
sudo touch /lib/systemd/system/liquidsoap.service; 
sudo touch /var/www/html/song.json
sudo chown $USER:$USER /var/www/html/song.json
sudo chmod 777 /var/www/html/song.json
sudo mkdir /var/www/html/hls
sudo mkdir /var/www/html/hls/persist
sudo chown $USER:$USER -R /var/www/html/hls
echo -e "\e[1;42mCreate and prepare relevant directories and permissions \e[0m : \e[1;32mSuccess\e[0m"
#================Configure icecast.xml and enable Iceacast service===============
sudo tee /etc/icecast2/icecast.xml <<EOF
<icecast>
    <!-- location and admin are two arbitrary strings that are e.g. visible
         on the server info page of the icecast web interface
         (server_version.xsl). -->
    <location>Earth</location>
    <admin>icemaster@localhost</admin>

    <!-- IMPORTANT!
         Especially for inexperienced users:
         Start out by ONLY changing all passwords and restarting Icecast.
         For detailed setup instructions please refer to the documentation.
         It's also available here: http://icecast.org/docs/
    -->

    <limits>
        <clients>100</clients>
        <sources>4</sources>
        <queue-size>524288</queue-size>
        <client-timeout>30</client-timeout>
        <header-timeout>15</header-timeout>
        <source-timeout>10</source-timeout>
        <!-- If enabled, this will provide a burst of data when a client 
             first connects, thereby significantly reducing the startup 
             time for listeners that do substantial buffering. However,
             it also significantly increases latency between the source
             client and listening client.  For low-latency setups, you
             might want to disable this. -->
        <burst-on-connect>0</burst-on-connect>
        <!-- same as burst-on-connect, but this allows for being more
             specific on how much to burst. Most people won't need to
             change from the default 65535. Applies to all mountpoints  -->
        <burst-size>0</burst-size>
    </limits>

    <authentication>
        <!-- Sources log in with username 'source' -->
        <source-password>vinylstation</source-password>
        <!-- Relays log in with username 'relay' -->
        <relay-password>VinylStation</relay-password>

        <!-- Admin logs in with the username given below -->
        <admin-user>admin</admin-user>
        <admin-password>VinylStation</admin-password>
    </authentication>

    <!-- set the mountpoint for a shoutcast source to use, the default if not
         specified is /stream but you can change it here if an alternative is
         wanted or an extension is required
    <shoutcast-mount>/live.nsv</shoutcast-mount>
    -->

    <!-- Uncomment this if you want directory listings -->
    <!--
    <directory>
        <yp-url-timeout>15</yp-url-timeout>
        <yp-url>http://dir.xiph.org/cgi-bin/yp-cgi</yp-url>
    </directory>
    -->

    <!-- This is the hostname other people will use to connect to your server.
         It affects mainly the urls generated by Icecast for playlists and yp
         listings. You MUST configure it properly for YP listings to work!
    -->
    <hostname>localhost</hostname>

    <!-- You may have multiple <listen-socket> elements -->
    <listen-socket>
        <port>8000</port>
        <!-- <bind-address>127.0.0.1</bind-address> -->
        <!-- <shoutcast-mount>/stream</shoutcast-mount> -->
    </listen-socket>
    <!--
    <listen-socket>
        <port>8080</port>
    </listen-socket>
    -->
    <!--
    <listen-socket>
        <port>8443</port>
        <ssl>1</ssl>
    </listen-socket>
    -->


    <!-- Global header settings 
         Headers defined here will be returned for every HTTP request to Icecast.

         The ACAO header makes Icecast public content/API by default
         This will make streams easier embeddable (some HTML5 functionality needs it).
         Also it allows direct access to e.g. /status-json.xsl from other sites.
         If you don't want this, comment out the following line or read up on CORS. 
    -->
    <http-headers>
        <header name="Access-Control-Allow-Origin" value="*" />
    </http-headers>


    <!-- Relaying
         You don't need this if you only have one server.
         Please refer to the documentation for a detailed explanation.
    -->
    <!--<master-server>127.0.0.1</master-server>-->
    <!--<master-server-port>8001</master-server-port>-->
    <!--<master-update-interval>120</master-update-interval>-->
    <!--<master-password>hackme</master-password>-->

    <!-- setting this makes all relays on-demand unless overridden, this is
         useful for master relays which do not have <relay> definitions here.
         The default is 0 -->
    <!--<relays-on-demand>1</relays-on-demand>-->

    <!--
    <relay>
        <server>127.0.0.1</server>
        <port>8080</port>
        <mount>/example.ogg</mount>
        <local-mount>/different.ogg</local-mount>
        <on-demand>0</on-demand>

        <relay-shoutcast-metadata>0</relay-shoutcast-metadata>
    </relay>
    -->


    <!-- Mountpoints
         Only define <mount> sections if you want to use advanced options,
         like alternative usernames or passwords
    -->

    <!-- Default settings for all mounts that don't have a specific <mount type="normal">.
    -->
    <!-- 
    <mount type="default">
        <public>0</public>
        <intro>/server-wide-intro.ogg</intro>
        <max-listener-duration>3600</max-listener-duration>
        <authentication type="url">
                <option name="mount_add" value="http://auth.example.org/stream_start.php"/>
        </authentication>
        <http-headers>
                <header name="foo" value="bar" />
        </http-headers>
    </mount>
    -->

    <!-- Normal mounts -->
    <!--
    <mount type="normal">
        <mount-name>/example-complex.ogg</mount-name>

        <username>othersource</username>
        <password>hackmemore</password>

        <max-listeners>1</max-listeners>
        <dump-file>/tmp/dump-example1.ogg</dump-file>
        <burst-size>65536</burst-size>
        <fallback-mount>/example2.ogg</fallback-mount>
        <fallback-override>1</fallback-override>
        <fallback-when-full>1</fallback-when-full>
        <intro>/example_intro.ogg</intro>
        <hidden>1</hidden>
        <public>1</public>
        <authentication type="htpasswd">
                <option name="filename" value="myauth"/>
                <option name="allow_duplicate_users" value="0"/>
        </authentication>
        <http-headers>
                <header name="Access-Control-Allow-Origin" value="http://webplayer.example.org" />
                <header name="baz" value="quux" />
        </http-headers>
        <on-connect>/home/icecast/bin/stream-start</on-connect>
        <on-disconnect>/home/icecast/bin/stream-stop</on-disconnect>
    </mount>
    -->

    <!--
    <mount type="normal">
        <mount-name>/auth_example.ogg</mount-name>
        <authentication type="url">
            <option name="mount_add"       value="http://myauthserver.net/notify_mount.php"/>
            <option name="mount_remove"    value="http://myauthserver.net/notify_mount.php"/>
            <option name="listener_add"    value="http://myauthserver.net/notify_listener.php"/>
            <option name="listener_remove" value="http://myauthserver.net/notify_listener.php"/>
            <option name="headers"         value="x-pragma,x-token"/>
            <option name="header_prefix"   value="ClientHeader."/>
        </authentication>
    </mount>
    -->

    <fileserve>1</fileserve>

    <paths>
        <!-- basedir is only used if chroot is enabled -->
        <basedir>/usr/share/icecast2</basedir>

        <!-- Note that if <chroot> is turned on below, these paths must both
             be relative to the new root, not the original root -->
        <logdir>/var/log/icecast2</logdir>
        <webroot>/usr/share/icecast2/web</webroot>
        <adminroot>/usr/share/icecast2/admin</adminroot>
        <!-- <pidfile>/usr/share/icecast2/icecast.pid</pidfile> -->

        <!-- Aliases: treat requests for 'source' path as being for 'dest' path
             May be made specific to a port or bound address using the "port"
             and "bind-address" attributes.
          -->
        <!--
        <alias source="/foo" destination="/bar"/>
        -->
        <!-- Aliases: can also be used for simple redirections as well,
             this example will redirect all requests for http://server:port/ to
             the status page
        -->
        <alias source="/" destination="/status.xsl"/>
        <!-- The certificate file needs to contain both public and private part.
             Both should be PEM encoded.
        <ssl-certificate>/usr/share/icecast2/icecast.pem</ssl-certificate>
        -->
    </paths>

    <logging>
        <accesslog>access.log</accesslog>
        <errorlog>error.log</errorlog>
        <!-- <playlistlog>playlist.log</playlistlog> -->
        <loglevel>3</loglevel> <!-- 4 Debug, 3 Info, 2 Warn, 1 Error -->
        <logsize>10000</logsize> <!-- Max size of a logfile -->
        <!-- If logarchive is enabled (1), then when logsize is reached
             the logfile will be moved to [error|access|playlist].log.DATESTAMP,
             otherwise it will be moved to [error|access|playlist].log.old.
             Default is non-archive mode (i.e. overwrite)
        -->
        <!-- <logarchive>1</logarchive> -->
    </logging>

    <security>
        <chroot>0</chroot>
        <!--
        <changeowner>
            <user>nobody</user>
            <group>nogroup</group>
        </changeowner>
        -->
    </security>
</icecast>
EOF
#sudo systemctl enable icecast2
echo -e "\e[1;42mConfigure Icecast and DO NOT enable service - run sudo systemctl enable icecast2 if your want do enable\e[0m : \e[1;32mSuccess\e[0m"


#================ Create LIQUIDSOAP Streaming Engine configuration with HLS output ===========
sudo tee /etc/liquidsoap/vinylfromWax.liq <<EOF
#!/home/$USER/.opam/default/bin/liquidsoap
# set the path and permissions for the logfile
settings.log.file.path := "/var/log/liquidsoap/VinylfromWax.log"
settings.log.file.perms := 777
settings.log.unix_timestamps := false
settings.encoder.metadata.cover := ["pic", "apic", "metadata_block_picture"]
settings.encoder.metadata.export := ["artist", "title", "album", "genre", "year", "url", "apic", "pic", "coverart"]
#settings.charset.encodings := ["ISO-8859-1"] #url encoding worked with this setting
#==============ALSA Settings==========
#settings.alsa.alsa_buffer := 0
#settings.alsa.periods := 0

#==============Input from soundcard
#s = (input.alsa(device = "pcm.default", self_sync=true):source(audio=pcm(stereo)))
s = input.pulseaudio(fallible=false)
s = amplify(2.2 ,s)
s = bass_boost(frequency=140.0 ,gain=1.2 ,s)
#======================FORMATS======================================================
#-----------------MP3 Stream with floating point encoder
#f = %mp3.cbr(samplerate=44100,bitrate=320)
#f = %ffmpeg(format="mp3", %audio(codec="libmp3lame", samplerate=44100, sample_format="s16", channels=2, b="320k"))
#-----------------FLAC stream with OGG encapsulation
#fflac = %ogg(%flac(samplerate=44100,channels=2,compression=5,bits_per_sample=16))
#fflac = %ffmpeg(format="ogg", %audio(codec="flac", samplerate=44100, sample_format="s16", channels=2))
#-----------------MP3 Stream with fixed point encoder SHINE
#f = %shine(channels=2,samplerate=44100,bitrate=320)
#-----------------OGG VORBIS stream
#fvorbis = %ogg(%vorbis.cbr(samplerate=44100, channels=2, bitrate=128))
#fvorbis = %ffmpeg(format="ogg", %audio(codec="libvorbis", samplerate=44100, sample_format="s16", channels=2, b="250k"))
#-----------------ACC stream for SONOS
#faac = %fdkaac(channels=2, samplerate=44100, bandwidth="auto", bitrate=96, afterburner=false, transmux="adts", sbr_mode=false)
#faac = %ffmpeg(format="adts", %audio(codec="libfdk-aac", samplerate=44100, sample_format="s16", channels=2, b="250k"))
#faac = %ffmpeg(format="adts", %audio(codec="aac", samplerate=44100, sample_format="s16", channels=2, b="192k"))


#===================================================================================
#=============Define a reference to hold coverart URL information============
current_coverart = ref ("")

#======Prepare source to accept metadata injection=========
s = insert_metadata(s)
#================ Metadata grab and update section =========================================
#======== Launch songrec to detect one song, output as JSON, insert metadata into source stream========
def metadataupdater()
  json =  process.read("/usr/sbin/songrec recognize --json")
  file.write(data=json, "/var/www/html/song.json")
let json.parse (parsed_data : {
  track : {
    subtitle : string,
    title : string,
    genres : {
      primary : string
    },
    images : {
      coverart : string,
    },
    sections : [
      {
        metadata : [{text : string, title : string}]?,
        metapages : [{caption : string, image : string}]?,
        tabname : string,
        type : string,
        url : string?
      }
    ],
    type : string,
    url : string?,

  }
}) = json

let title = parsed_data.track.title
let subtitle = parsed_data.track.subtitle
let coverart = parsed_data.track.images.coverart
let genre = parsed_data.track.genres.primary
let sections = parsed_data.track.sections

#code provided by @vitoyucepi to get the deeply nested metadata under sections
metadata_list =
  try
    metadata_section = list.find(fun(section) -> section.metadata != null, sections)
    list.map(
      fun(metadata_item) -> (metadata_item.title, metadata_item.text),
      null.get(metadata_section.metadata)
    )
  catch err do
    log.important("Metadata processing failed: #{err}")
    []
  end

let album = metadata_list["Album"]
#let label = metadata_list["Label"]    
let year = metadata_list["Released"]    
#=========Debug lines, not needed for actual script===========    
#print ("Genre: #{genre}")
#print("Album: #{album}")
#print("Label: #{label}")
#print("Year: #{year}")   
#print("Found track #{title}, artist is #{subtitle}, cover art url is #{coverart}")
	pict = process.read("curl #{coverart} | base64 -i")

#Here are different options to prepare the URL coverart string for SONOS coverart injection. SONOS requires two string parts separated by a NUL character.
#See https://docs.sonos.com/docs/supported-audio-formats#tag/playback/operation/Playback-LoadContent-GroupId for information. Beware the typos in their WXXX tag example: neither include <> nor "" within the string!
  current_coverart := 'artworkURL_400x\x00'^coverart #This Hex format NUL character formatting works!
  #current_coverart := '<artworkURL_400x␀'^coverart^'>' #NUL CHaracter
  #current_coverart := 'artworkURL_400x\u{0000}'^coverart #UNICODE NUL CHaracter
  
  s.insert_metadata([("title", title),("artist", subtitle),("pic", pict),("coverart", coverart),("album", album),("year", year),("genre", genre),("url",current_coverart())]) 
  #print("HLS Current_Coverart tag reads #{current_coverart()}")
end

#This is an intermediate function to be called from blank.detect and output.icecast on_start.
#This intermediate function runs the actual mediadata updater in a thread, so that the
#metadata update does *not* interrupt the stream.
def handleblank() 
 thread.run(metadataupdater)
end

#Attach blank.detect capabilities to source
s = blank.detect(
  threshold=-21.,
  max_blank=1.,
  start_blank=true,
  track_sensitive=true,
  s)
#Launch on_noise callback
s.on_noise(synchronous=false, fun () -> begin handleblank() end)

#==============CREATE HTTP SERVER FOR METADATA OUTPUT================
meta = ref([])

# s = some source
s.on_metadata(synchronous=false,fun (m) -> meta := m)
# Return the json content of meta
def get_meta(_, response) =
  response.json(meta())
end

# Register get_meta at port 700
harbor.http.register(port=7000,method="GET","/getmeta",get_meta)

#===========PREPARE HLS SETTINGS=================
#< removing aac_lofi and aac_midfi settings  - one HLS stream is enough for local in-house service
aac_lofi = %ffmpeg(
    format="adts",
    %audio(
        codec="aac",
        samplerate=44100,
        channels=2,
       b="96k")).{
        # Adds an extra tag to this stream.
       id3_version=4,
       replay_id3=true,
    }
    
aac_midfi = %ffmpeg(
    format="adts",
    %audio(
        codec="aac",
       samplerate=44100,
        channels=2,
        b="128k",
        )
).{
        # Adds an extra tag to this stream.
       id3_version=4,
       replay_id3=true,
}
>#
aac_hifi = %ffmpeg(
    format="adts", #metadata successfully sent with adts
    %audio(
        codec="aac",
        samplerate=44100,
        channels=2,
        b="256k",
        )
).{
        # Adds an extra tag to this stream.
       id3_version=4,
       replay_id3=true,
   }

# Put them all together 
hls_streams = [
#		("aac_lofi", aac_lofi), 
#		("aac_midfi", aac_midfi), 
		("aac_hifi", aac_hifi)]

def hls_segment_name(metadata) =
  timestamp = int_of_float(time())
  let {stream_name, duration, position, extname} = metadata
  "#{stream_name}_#{duration}_#{timestamp}_#{position}.#{extname}"
end


#=================OUTPUT==================
#<
#-------------HLS Output via harbor - not recommended by savonet -------------
output.harbor.hls(playlist="vinylstation.m3u8",
    segment_duration=0.5,
    segments=6,
    segments_overhead=3,
    segment_name=hls_segment_name,
    port=8080,
    persist_at="/etc/liquidsoap/hls/persist",
    #"/etc/liquidsoap/hls",
    hls_streams,
    s)
>#
#-------------HLS Output via file-------------
output.file.hls(playlist="vinylstation.m3u8",
    segment_duration=2.0,
    segments=10,
    segments_overhead=5,
    segment_name=hls_segment_name,
    #port=8080,
    persist_at="/var/www/html/hls/persist",
    "/var/www/html/hls",
    hls_streams,
    s)


#---------------Icecast Output-------------------

#<========== Disabled Outputs ============
#---------------------MP3------------------------
output.icecast(f, 
host = "127.0.0.1", 
port = 8000, 
password = "vinylstation", 
mount = "vinyl", 
name = "Vinyl from Wax",
id="Vinyl Station", 
on_start=handleblank,
send_icy_metadata=true,
description="VinylStation - powered by Technics turntables",
#url="http://IP-ADDRESS&#8221;,
s)
#-----------------OGG/Vorbis--------------------
output.icecast(fvorbis,
host = "127.0.0.1",
port = 8000,
password = "vinylstation",
mount = "vinylogg",
name = "Vinyl from Wax",
id="Vinyl Station",
#send_icy_metadata=true,
description="VinylStation - powered by Technics turntables",
s) 

output.icecast(fvorbis,
host = "127.0.0.1",
port = 8000,
password = "vinylstation",
mount = "vinylogg.ogg",
name = "Vinyl from Wax",
id="Vinyl Station",
#send_icy_metadata=true,
description="VinylStation - powered by Technics turntables",
s) 

output.icecast(fflac,
host = "127.0.0.1",
port = 8000,
password = "vinylstation",
mount = "vinylflac",
name = "Vinyl from Wax",
id="Vinyl Station",
description="VinylStation - powered by Technics turntables",
s) 

output.icecast(faac,
host = "127.0.0.1",
port = 8000,
password = "vinylstation",
mount = "vinylaac",
name = "Vinyl from Wax",
id="Vinyl Station",
#send_icy_metadata=true,
description="VinylStation - powered by Technics turntables",
s)
================================>#
EOF
sudo sed -i "s/\$USER/$USER/g" /etc/liquidsoap/vinylfromWax.liq
echo -e "\e[1;42mCreate LIQUIDSOAP Streaming Engine configuration with HLS output\e[0m : \e[1;32mSuccess\e[0m"
#================Congifure sound interface for liquidsoap=================

sudo tee /etc/asound.conf <<EOF
#goes into /etc/
#This config is for use with PulseAudio
pcm.!default {
    type hw
    card 0
    device 0
    format S16_LE
    channels 2
    rate 44100
    period_size 1024
    buffer_size 4096
}

#What you see here below are configs that worked well with ALSA
#pcm.!default {
#    type plug
#    slave.pcm "liquidsoap"
#}

#pcm.liquidsoap {
#    type dsnoop
#    ipc_key 5978293 # Unique IPC key
#    ipc_key_add_uid yes
#    slave {
#      pcm "hw:0,0"
#      channels 2
#      rate 44100        # Set sample rate to 44.1 kHz
#      period_size: 661
#      buffer_size: 2644
#      #period_size 1024  # Frames per period (low latency: 23.2 ms)
#      #buffer_size 4096  # Total buffer size (92.9 ms total latency)
#   }
#   bindings {
#       0 0
#       1 1
#   }
#}
EOF
echo -e "\e[1;42mCreate ALSA configuration file, PulseAudio version - see notes inside /etc/asound.conf \e[0m : \e[1;32mSuccess\e[0m"

#========================= Configure liquidsoap.service

sudo tee /lib/systemd/system/liquidsoap.service <<EOF

#goes into /lib/systemd/system/
[Unit]
Description=Liquidsoap Stream Engine
After=multi-user.target

[Service]
ExecStart=/home/$USER/.opam/liquidsoap/bin/liquidsoap /etc/liquidsoap/vinylfromWax.liq
Restart=always
User=$USER

[Install]
WantedBy=multi-user.target
EOF

sudo sed -i "s/\$USER/$USER/g" /lib/systemd/system/liquidsoap.service
echo -e "\e[1;42mConfigure liquidsoap.service\e[0m : \e[1;32mSuccess\e[0m"
#=================================Configure NGINX with HLS streamer
sudo tee /etc/nginx/sites-available/HLS-vinylstation.conf <<EOF

#based on https://github.com/radiofrance/rf-liquidsoap/blob/master/example/nginx/hls.conf
server {
  listen 8080;
  server_name _;
  root /var/www/html/hls;

  types {
    application/vnd.apple.mpegurl m3u8;
    video/mp2t ts;
  }

  location ~ \.(ts|m3u8)$ {
    add_header Allow "GET, HEAD" always;
    if ( $request_method !~ ^(GET|HEAD)$ ) {
      return 405;
    }

    root /var/www/html/hls;

    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET';
    add_header 'Access-Control-Allow-Headers' '*';

    location ~ \.(ts)$ {
      add_header 'Cache-Control' 'public, max-age=660';
    }

    location ~ (lofi|midfi|hifi)\.(m3u8)$ {
      add_header 'Cache-Control' 'max-age=1';
    }

    location ~ \.(m3u8)$ {
      add_header 'Cache-Control' 'max-age=600';
    }
  }

  location / {
    autoindex on;
    autoindex_format html;
  }
}


EOF
sudo ln -s /etc/nginx/sites-available/HLS-vinylstation.conf /etc/nginx/sites-enabled
#echo -e "\e[1;42mConfigure NGINX with HLS streamer\e[0m : \e[1;31mNOT ACTIVATED\e[0m \n\e[1;43mThe configuration file is ready, but is not enabled, as liquidsoap harbor serves the files.\e[0m\nIf you want to activate the NGINX HLS server configuration:\n1. In the liquidsoap configuration file: \e[1;31m disable liquidsoap output.harbor.hls,\e[1;32m activate output.file.hls\e[0m \n2. run this command: \e[1;33mln -s /etc/nginx/sites-enabled/ /etc/sites-available/HLS-vinylstation.conf\e[0m"

#=======================Get FFMPEG Source & Compile====================
echo -e "\e[1;42mPrepare the long and winding road to compiling FFmpeg with aac support\e[0m"
sudo apt-get -y install autoconf automake build-essential cmake doxygen libtool pkg-config python3-dev python3-pip git
cd ~
mkdir ~/ffmpeg-libraries
#----------Compile AAC Support
echo -e "\e[1;42mGet FFmpeg fdk-aac libraries\e[0m"
git clone --depth 1 https://github.com/mstorsjo/fdk-aac.git ~/ffmpeg-libraries/fdk-aac \
  && cd ~/ffmpeg-libraries/fdk-aac \
  && autoreconf -fiv \
  && ./configure \
  && make -j$(nproc) \
  && sudo make install ;
cd ~ ;
echo -e "\e[1;42mGet FFmpeg source (v.7.1.1)\e[0m"
#curl -L https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2 | tar -xj && cd ffmpeg; #this gets latest snapshot; might not compile correctly though
curl -L https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz | tar -xJ && cd ffmpeg-7.1.1; #This gets said version of ffmpeg.

echo -e "\e[1;42mCompile FFmpeg with fdk-aac libvorbis libmp3lame flac\e[0m"
./configure --enable-shared  --enable-libfdk-aac --enable-libvorbis --enable-libmp3lame --enable-pic && make && sudo make install && sudo ldconfig
echo -e "\e[1;42mCompile FFmpeg with fdk-aac libvorbis libmp3lame flac\e[0m : \e[1;32mSuccess\e[0m"

#=======================Get SONGREC Source & compile===================
echo -e "\e[1;42mGet songrec opensource Shazam client and compile\e[0m"
sudo apt-get update && sudo apt-get -y upgrade
sudo apt-get -y install mercurial git darcs bubblewrap
cd ~
curl https://sh.rustup.rs -sSf | sh

echo "export PATH="$HOME/.cargo/bin:$PATH"" | tee -a ~/.profile ~/.bashrc
export PATH="$HOME/.cargo/bin:$PATH"
source ~/.bashrc

sudo apt install build-essential libasound2-dev libgtk-3-dev libssl-dev -y
cd ~
git clone https://github.com/marin-m/songrec
cd songrec
cargo build --release --no-default-features -F ffmpeg,mpris
sudo mv ~/songrec/target/release/songrec /usr/sbin/
echo -e "\e[1;42mGet songrec opensource Shazam client and compile\e[0m : \e[1;32mSuccess\e[0m"

#=======================Get liquidsoap rolling release source & compile===================
echo -e "\e[1;42mGet liquidsoap rolling release source & compile\e[0m"
cd ~
opam pin -ny git+https://github.com/savonet/liquidsoap
check_status "Pin Liquidsoap repository failed."

#Line below generates some package conflicts in recent versions
#opam install -y ssl ocurl taglib mad lame vorbis cry alsa pulseaudio shine flac ffmpeg liquidsoap
#Following line prefers FFmpeg for lame, vorbis
opam install -y ocurl taglib mad lame cry alsa pulseaudio shine ffmpeg liquidsoap
check_status "Install Liquidsoap and dependencies failed."

sudo systemctl enable liquidsoap.service
echo -e "\e[1;42mGet liquidsoap rolling release source & compile : \e[1;32mSuccess\e[0m"
echo -e "\e[1;42mVinylstation successfully installed\e[0m\n
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▒▓▒░░░░░░░░░░░░░░░
░░░░░░░░▒▒▓▒▒▒▒▓▒▒▒▒▒▒▓▓▒▒▒▒▒▒░░░░░░▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒░░░░░░▓▓▓▓▓▓▓▒░░░░░░░░
░░░░░░░▒██░░░░░▓███▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓██████████▓░▒░░░░░▒██████▒░░░░░░░
░░░░░░░███▓▓▒▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓███▓▓█▓▒░░░░▒▒░░▓▒▓██▓░░░░░░░
░░░░░░▒█████▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓█░░▒▒░▒█░░░▒▓▒▓██░░░░░░░
░░░░░░▓███▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓██▓▒▒▒▒░░▒▒█▓████▓░░░░░░
░░░░░░██▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▓▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒█████▓▓░█████████░░░░░░
░░░░░▓█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▒▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓█████▒░▓███████▒░░░░░
░░░░░█▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒██████░░████████░░░░░
░░░░▒█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓░▒▒▒█████▓░▓█▓▓▓▓███▒░░░░
░░░░██▒▒▓▒▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▒▒▒▒▒███▒░░▓███▓▓█▓███░░░░
░░░▒███▒▒▒▒▒▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▒▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒██▓▓▓▒▓████▓▒▒▒███▒░░░
░░░▓▓▓▓▓▒▒▒▒░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒░▒▒▒▒▓▓▒▓▓███████▓▒░░▓██▓░░░
░░░█▒▒▒▒▒▒░▒▒▒░▒▒▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒░▒▒▒▒▒███▓▓▓█████████▓█▓▓███░░░
░░▓█▓▒░▒▒██▓▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒░░░▒▒▒▒▒▓█████████████████▓█▓████▓░░
░░█▓▒▒▒▒▒▒▓███▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░▒▒▒░░░▒▓▓████████████████████████████░░
░▒█▒░░░░░░▒█▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░▒▓█████████████████████████████▒░
░██▓▓▓▓▓▓▓██▓▓▓▓▓▓▓▓█████▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████▓▓▓▓██████████████████████████████░
░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░
░▒▓▓▓▓█████████████████████████████████████████████████████████████████████████░
░░▓▓████████████████▓█▓▓▓▓███████████████████████████████████████████████████▓▒░
░░░░▒▓▓██▓▓█░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▒▓▓▓███▓▒░░░
░░░░▓██████▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▓██████▒░░░
"
# 10-second countdown before reboot
for i in {10..1}; do
    echo -e "\e[1;31m System reboot in $i \e[0m seconds."
    sleep 1
done
# Reboot the system to apply all configurations
sudo reboot
