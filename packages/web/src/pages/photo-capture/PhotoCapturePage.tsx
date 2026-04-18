import { useState, useRef, useEffect } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import { Camera, Upload, CheckCircle2, X, Loader2, ImageIcon, AlertCircle } from 'lucide-react';
import axios from 'axios';
import toast from 'react-hot-toast';

export function PhotoCapturePage() {
  const { ticketId, deviceId } = useParams<{ ticketId: string; deviceId: string }>();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('t');

  const [photos, setPhotos] = useState<{ file: File; preview: string }[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploaded, setUploaded] = useState(false);
  const [error, setError] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);
  const photosRef = useRef(photos);
  photosRef.current = photos;

  // Revoke all object URLs on unmount to prevent memory leaks
  useEffect(() => {
    return () => {
      photosRef.current.forEach((p) => URL.revokeObjectURL(p.preview));
    };
  }, []); // mount-only

  const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

  const handleCapture = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (!files.length) return;

    const valid: File[] = [];
    for (const file of files) {
      if (!file.type.startsWith('image/')) {
        toast.error(`"${file.name}" is not an image file`);
        continue;
      }
      if (file.size > MAX_FILE_SIZE) {
        toast.error(`"${file.name}" exceeds the 10 MB size limit`);
        continue;
      }
      valid.push(file);
    }
    if (!valid.length) { if (fileInputRef.current) fileInputRef.current.value = ''; return; }

    const newPhotos = valid.map((file) => ({
      file,
      preview: URL.createObjectURL(file),
    }));
    setPhotos((prev) => [...prev, ...newPhotos]);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const removePhoto = (index: number) => {
    setPhotos((prev) => {
      URL.revokeObjectURL(prev[index].preview);
      return prev.filter((_, i) => i !== index);
    });
  };

  const handleUpload = async () => {
    if (!photos.length || !ticketId || !deviceId || !token) return;
    setUploading(true);
    setError('');
    try {
      const formData = new FormData();
      photos.forEach((p) => formData.append('photos', p.file));
      formData.append('ticket_device_id', deviceId);
      formData.append('type', 'pre');
      await axios.post(`/api/v1/tickets/${ticketId}/photos`, formData, {
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'multipart/form-data' },
      });
      setUploaded(true);
    } catch (e: any) {
      setError(e?.response?.data?.message || 'Upload failed. Please try again.');
    } finally {
      setUploading(false);
    }
  };

  if (!token) {
    return (
      <div className="min-h-screen bg-gray-900 flex flex-col items-center justify-center p-6 text-center">
        <AlertCircle className="h-16 w-16 text-red-400 mb-4" />
        <h1 className="text-xl font-bold text-white mb-2">Invalid Link</h1>
        <p className="text-gray-400 text-sm">This photo link is missing authentication. Please scan the QR code again from the check-in screen.</p>
      </div>
    );
  }

  if (uploaded) {
    return (
      <div className="min-h-screen bg-gray-900 flex flex-col items-center justify-center p-6 text-center">
        <div className="h-28 w-28 rounded-full bg-green-500/20 flex items-center justify-center mb-6">
          <CheckCircle2 className="h-14 w-14 text-green-400" />
        </div>
        <h1 className="text-2xl font-bold text-white mb-2">Photos Saved!</h1>
        <p className="text-gray-400 mb-1">
          {photos.length} photo{photos.length !== 1 ? 's' : ''} added to ticket #{ticketId}
        </p>
        <p className="text-gray-600 text-sm mt-4">You can close this page now.</p>
        <button
          onClick={() => { setUploaded(false); setPhotos([]); }}
          className="mt-6 px-6 py-3 bg-primary-600 text-white rounded-2xl font-semibold text-sm"
        >
          Add More Photos
        </button>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-900 flex flex-col">
      {/* Header */}
      <div className="bg-gray-800 px-4 py-4 flex items-center gap-3 border-b border-gray-700 safe-area-top">
        <div className="h-10 w-10 rounded-xl bg-primary-600/20 flex items-center justify-center">
          <Camera className="h-5 w-5 text-primary-400" />
        </div>
        <div>
          <h1 className="text-white font-semibold leading-tight">Device Photos</h1>
          <p className="text-gray-400 text-xs">Ticket #{ticketId} — Pre-condition</p>
        </div>
      </div>

      {/* Instructions */}
      <div className="px-4 py-3 bg-primary-900/20 border-b border-primary-800/30">
        <p className="text-primary-300 text-sm text-center leading-relaxed">
          📸 Take photos of the device <strong>before repair</strong> — screen, damage, cosmetic condition
        </p>
      </div>

      {/* Photo grid */}
      {photos.length > 0 ? (
        <div className="p-4 grid grid-cols-2 gap-3">
          {photos.map((photo, i) => (
            <div key={i} className="relative aspect-square rounded-2xl overflow-hidden bg-gray-800 shadow-lg">
              <img src={photo.preview} alt={`Photo ${i + 1}`} className="w-full h-full object-cover" />
              <button
                onClick={() => removePhoto(i)}
                className="absolute top-2 right-2 h-8 w-8 rounded-full bg-black/70 flex items-center justify-center active:scale-95"
              >
                <X className="h-4 w-4 text-white" />
              </button>
              <div className="absolute bottom-2 left-2 bg-black/60 rounded-lg px-2 py-0.5">
                <span className="text-white text-xs font-medium">#{i + 1}</span>
              </div>
            </div>
          ))}
          {/* Add more tile */}
          <label className="aspect-square rounded-2xl border-2 border-dashed border-gray-600 flex flex-col items-center justify-center cursor-pointer active:bg-gray-800 transition-colors">
            <Camera className="h-8 w-8 text-gray-500 mb-1" />
            <span className="text-gray-500 text-xs">Add more</span>
            <input
              type="file"
              accept="image/*"
              capture="environment"
              multiple
              className="sr-only"
              onChange={handleCapture}
            />
          </label>
        </div>
      ) : (
        /* Empty state */
        <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
          <div className="h-24 w-24 rounded-full bg-gray-800 flex items-center justify-center mb-5">
            <ImageIcon className="h-12 w-12 text-gray-600" />
          </div>
          <p className="text-gray-300 font-medium mb-1">No photos yet</p>
          <p className="text-gray-600 text-sm">Tap the camera button below to photograph the device</p>
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="mx-4 mb-2 px-4 py-3 bg-red-900/30 border border-red-700/50 rounded-2xl text-red-300 text-sm text-center flex items-center gap-2">
          <AlertCircle className="h-4 w-4 flex-shrink-0" />
          {error}
        </div>
      )}

      {/* Bottom actions */}
      <div className="mt-auto p-4 space-y-3 border-t border-gray-700/50 safe-area-bottom">
        {/* Camera button */}
        <label className="flex items-center justify-center gap-3 w-full py-5 bg-primary-600 active:bg-primary-700 text-white rounded-2xl font-semibold text-lg cursor-pointer transition-colors select-none shadow-lg">
          <Camera className="h-6 w-6" />
          {photos.length > 0 ? 'Take Another Photo' : 'Take Photo'}
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            capture="environment"
            multiple
            className="sr-only"
            onChange={handleCapture}
          />
        </label>

        {/* Upload */}
        {photos.length > 0 && (
          <button
            onClick={handleUpload}
            disabled={uploading}
            className="flex items-center justify-center gap-3 w-full py-5 bg-green-600 active:bg-green-700 text-white rounded-2xl font-semibold text-lg transition-colors disabled:opacity-60 shadow-lg"
          >
            {uploading ? (
              <><Loader2 className="h-6 w-6 animate-spin" /> Uploading...</>
            ) : (
              <><Upload className="h-6 w-6" /> Save {photos.length} Photo{photos.length !== 1 ? 's' : ''}</>
            )}
          </button>
        )}

        <p className="text-gray-600 text-xs text-center">
          {photos.length}/20 photos · Saved directly to the repair ticket
        </p>
      </div>
    </div>
  );
}
