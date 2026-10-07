package dev.revev.audiofixture;
import android.app.*;
import android.content.*;
import android.media.*;
import android.os.*;

// Separate test APK: exercises actual Android focus delivery, not a production hook.
public class FocusService extends Service {
    private volatile boolean running = true;
    private volatile AudioFocusRequest request;
    private AudioManager manager;
    public android.os.IBinder onBind(Intent intent) { return null; }
    public void onCreate() {
        super.onCreate();
        NotificationManager notifications = getSystemService(NotificationManager.class);
        notifications.createNotificationChannel(new NotificationChannel("test", "Audio test", NotificationManager.IMPORTANCE_LOW));
        startForeground(1, new Notification.Builder(this,"test").setSmallIcon(android.R.drawable.ic_media_play).setContentTitle("RevEV interruption test").build());
        manager = getSystemService(AudioManager.class);
        new Thread(() -> {
            try {
                for(int i=0;i<8 && running;i++) {
                    int kind = i%2==0 ? AudioManager.AUDIOFOCUS_GAIN_TRANSIENT : AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK;
                    request = new AudioFocusRequest.Builder(kind)
                        .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                        .setOnAudioFocusChangeListener(change -> {},new Handler(Looper.getMainLooper())).build();
                    int result = manager.requestAudioFocus(request);
                    android.util.Log.i("RevEVFocusFixture","request="+kind+" result="+result);
                    Thread.sleep(2500);
                    manager.abandonAudioFocusRequest(request);
                    request = null;
                    Thread.sleep(4500);
                }
            } catch(InterruptedException ignored) {} finally { stopSelf(); }
        },"focus-fixture").start();
    }
    public void onDestroy() {
        running=false;
        AudioFocusRequest current = request;
        if(current!=null) manager.abandonAudioFocusRequest(current);
        super.onDestroy();
    }
}
