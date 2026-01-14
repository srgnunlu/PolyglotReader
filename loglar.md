[13:47:25.089] ℹ️ [LibraryViewModel] Klasör ve etiketler yüklendi
   └─ 3 klasör, 48 etiket
[GoogleGenerativeAI] Model gemini-3-flash-preview initialized. To enable additional logging, add `-GoogleGenerativeAIDebugLogEnabled` as a launch argument in Xcode.
[GoogleGenerativeAI] Model gemini-3-flash-preview initialized. To enable additional logging, add `-GoogleGenerativeAIDebugLogEnabled` as a launch argument in Xcode.
[GoogleGenerativeAI] Model gemini-3-flash-preview initialized. To enable additional logging, add `-GoogleGenerativeAIDebugLogEnabled` as a launch argument in Xcode.
[13:47:26.834] ℹ️ [RAGEmbeddingService] Disk cache yüklendi
   └─ 767 embedding bulundu
[13:47:26.834] ℹ️ [RAGService] Profesyonel RAG Servisi başlatıldı v2.0 (Facade)
[13:47:26.834] 🔍 [PDFReaderView] View appeared for file: ATLS_11thEdition 1.pdf
[13:47:26.870] ℹ️ [PDFImageService] Servis başlatıldı
[13:47:26.870] 🔍 [PDFReaderView] Task started
[13:47:26.870] ℹ️ [PDFReaderVM] PDF yükleniyor: ATLS_11thEdition 1.pdf
[13:47:26.870] ℹ️ [PDFCacheService] PDF Cache Servisi başlatıldı
[13:47:26.870] ℹ️ [PDFCacheService] Cache hit ✓
   └─ 2a632478-1ac8-4ac9-9ac4-c683dc50d9d0/1768246190_ATLS_11thEdition_1.pdf - 45 MB
[13:47:26.870] ℹ️ [PDFReaderVM] 📦 Cache'den yüklendi
   └─ 45 MB
[13:47:26.870] 🔍 [SupabaseStorageService] Getting signed URL for: 2a632478-1ac8-4ac9-9ac4-c683dc50d9d0/1768246190_ATLS_11thEdition_1.pdf
[13:47:26.870] 🔍 [Supabase] Request: POST https://tftmypxwgccdgvldhaya.supabase.co/storage/v1/object/sign/user_files/2a632478-1ac8-4ac9-9ac4-c683dc50d9d0/1768246190_ATLS_11thEdition_1.pdf
Body: {
  "expiresIn" : 3600
}
   └─ Request: POST https://tftmypxwgccdgvldhaya.supabase.co/storage/v1/object/sign/user_files/2a632478-1ac8-4ac9-9ac4-c683dc50d9d0/1768246190_ATLS_11thEdition_1.pdf
Body: {
  "expiresIn" : 3600
}
context: ["requestID": 3250DB92-5300-49F3-9B2A-5C9521F438A8]
[13:47:27.443] 🔍 [Supabase] Response: Status code: 200 Content-Length: 441
Body: {
  "signedURL" : "\/object\/sign\/user_files\/2a632478-1ac8-4ac9-9ac4-c683dc50d9d0\/1768246190_ATLS_11thEdition_1.pdf?token=<redacted>
}
   └─ Response: Status code: 200 Content-Length: 441
Body: {
  "signedURL" : "\/object\/sign\/user_files\/2a632478-1ac8-4ac9-9ac4-c683dc50d9d0\/1768246190_ATLS_11thEdition_1.pdf?token=<redacted> <truncated 160 chars>
[13:47:27.526] 🔍 [PDFReaderVM] URL alındı
   └─ https://tftmypxwgccdgvldhaya.supabase.co/storage/v1/object/sign/user_files/2a632478-1ac8-4ac9-9ac4-c683dc50d9d0/1768246190_ATLS_11thEdition_1.pdf?token=<redacted>
[13:47:27.526] ℹ️ [PDFReaderVM] PDF yüklendi
   └─ 208 sayfa
[13:47:27.526] ℹ️ [PDFReaderVM] AI Chat hazırlanıyor...
[13:47:27.526] 🔍 [PDFReaderView] Task finished
[13:49:16.672] 🔍 [UI] PDFKitView appeared in hierarchy
[13:49:16.681] 🔍 [Supabase] Request: GET https://tftmypxwgccdgvldhaya.supabase.co/rest/v1/annotations?select=*&file_id=eq.8ef212cc-e16f-40c7-86c0-367472c468b3
Body: <none>
   └─ Request: GET https://tftmypxwgccdgvldhaya.supabase.co/rest/v1/annotations?select=*&file_id=eq.8ef212cc-e16f-40c7-86c0-367472c468b3
Body: <none>
context: ["requestID": 83BC1C42-BDAA-414E-B620-BF299C59168B]
[13:49:16.681] 🔍 [Supabase] Request: GET https://tftmypxwgccdgvldhaya.supabase.co/rest/v1/reading_progress?select=*&file_id=eq.8ef212cc-e16f-40c7-86c0-367472c468b3&user_id=eq.2A632478-1AC8-4AC9-9AC4-C683DC50D9D0&limit=1
Body: <none>
   └─ Request: GET https://tftmypxwgccdgvldhaya.supabase.co/rest/v1/reading_progress?select=*&file_id=eq.8ef212cc-e16f-40c7-86c0-367472c468b3&user_id=eq.2A632478-1AC8-4AC9-9AC4-C683DC50D9D0&limit=1
Body: <none>
context: ["requestID": 0410C495-5B0B-4EBF-AA5E-8897D0B04C88]
[13:49:16.681] 🔍 [Supabase] Response: Status code: 200 Content-Length: 258
Body: [
  {
    "file_id" : "8ef212cc-e16f-40c7-86c0-367472c468b3",
    "id" : "d59cfb9a-215f-4092-a474-d013096d434f",
    "offset_x" : 0,
    "offset_y" : 444.3603515625,
    "page" : 3,
    "updated_at" : "2026-01-12T20:12:08.618273+00:00",
    "user_id" : "2a632478-1ac8-4ac9-9ac4-c683dc50d9d0",
    "zoom_scale" : 1.2
  }
]
   └─ Response: Status code: 200 Content-Length: 258
Body:  [
  {
    "file_id" : "8ef212cc-e16f-40c7-86c0-367472c468b3",
    "id" : "d59cfb9a-215f-4092-a474-d013096d434f",
    "offset_x" : 0,
    "offset_y" : 444.3603515625,
    "page" : 3,
    "updated_at" ... <truncated 122 chars>
context: ["requestID": 0410C495... <truncated 29 chars>
[13:49:16.683] 🔍 [Supabase] Response: Status code: 200 Content-Length: 6263
Body: [
  {
    "created_at" : "2026-01-12T20:06:14.172912+00:00",
    "data" : {
      "color" : "#fef08a",
      "isAiGenerated" : false,
      "rects" : [
        {
          "height" : 13.740000000000009,
          "width" : 261.02800000000013,
          "x" : 36,
          "y" : 678.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 260.96799999999996,
          "x" : 36,
          "y" : 666.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 261.00000000000011,
          "x" : 36,
          "y" : 654.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 261.00799999999998,
          "x" : 36,
          "y" : 642.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 261.02700000000004,
          "x" : 36,
          "y" : 630.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 260.99900000000008,
          "x" : 36,
          "y" : 618.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 261.01900000000001,
          "x" : 36,
          "y" : 606.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 261,
          "x" : 36,
          "y" : 594.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 260.98599999999999,
          "x" : 36,
          "y" : 582.68380000000002
        },
        {
          "height" : 13.740000000000009,
          "width" : 175.42400000000001,
          "x" : 36,
          "y" : 570.68380000000002
        }
      ],
      "text" : "patient is universal, but practice settings, available resources,\nlanguages, and mechanisms of injury are not. The combined\nefforts of committed leaders from around the world have been\nsuccessful in advancing the quality of the Advanced Trauma\nLife Support® (ATLS®) Course by ensuring that course content\nis relevant in all countries and systems that possess any degree\nof infrastructure to support trauma care. The ATLS Course was\ndesigned to provide physicians and other healthcare professionals\nwith a concise and structured approach to assessing and managing\npatients with multiple injuries, using a com"
    },
    "file_id" : "8ef212cc-e16f-40c7-86c0-367472c468b3",
    "id" : "5E977026-7271-4D25-8FA9-EC7067A75CE7",
    "is_favorite" : false,
    "page" : 4,
    "type" : "highlight",
    "updated_at" : "2026-01-12T20:06:14.172912+00:00",
    "user_id" : "2a632478-1ac8-4ac9-9ac4-c683dc50d9d0"
  },
  {
    "created_at" : "2026-01-12T20:12:18.778629+00:00",
    "data" : {
      "color" : "#bae6fd",
      "isAiGenerated" : false,
      "rects" : [
        {
          "height" : 1.4473684210526316,
          "width" : 39.689998802570479,
          "x" : 8.6999906866593051,
          "y" : 29.378083881578949
        },
        {
          "height" : 1.2582236842105263,
          "width" : 42.494295578824129,
          "x" : 5.8793789332233466,
          "y" : 31.028988486842106
        },
        {
          "height" : 1.4473684210526316,
          "width" : 42.494295578824129,
          "x" : 5.8793789332233466,
          "y" : 30.897409539473685
        },
        {
          "height" : 1.2582236842105263,
          "width" : 12.738687617248306,
          "x" : 5.8793789332233466,
          "y" : 32.5390625
        },
        {
          "height" : 1.4473684210526316,
          "width" : 12.738687617248306,
          "x" : 5.8793789332233466,
          "y" : 32.407483552631575
        },
        {
          "height" : 1.2582236842105263,
          "width" : 0.86962487194156535,
          "x" : 18.669256662364791,
          "y" : 32.5390625
        },
        {
          "height" : 1.4473684210526316,
          "width" : 0.86962487194156535,
          "x" : 18.669256662364791,
          "y" : 32.407483552631575
        },
        {
          "height" : 1.2582236842105263,
          "width" : 28.89149625470656,
          "x" : 19.528744960817445,
          "y" : 32.5390625
        },
        {
          "height" : 1.4473684210526316,
          "width" : 28.89149625470656,
          "x" : 19.528744960817445,
          "y" : 32.407483552631575
        },
        {
          "height" : 1.2582236842105263,
          "width" : 24.95774071659504,
          "x" : 5.8793789332233466,
          "y" : 34.059416118421055
        },
        {
          "height" : 1.4473684210526316,
          "width" : 24.95774071659504,
          "x" : 5.8793789332233466,
          "y" : 33.92783717105263
        },
        {
          "height" : 1.2582236842105263,
          "width" : 0.90605500192919197,
          "x" : 30.909647290483093,
          "y" : 34.059416118421055
        },
        {
          "height" : 1.4473684210526316,
          "width" : 0.90605500192919197,
          "x" : 30.909647290483093,
          "y" : 33.92783717105263
        },
        {
          "height" : 1.2582236842105263,
          "width" : 16.694994744614895,
          "x" : 31.779779406873242,
          "y" : 34.059416118421055
        },
        {
          "height" : 1.4473684210526316,
          "width" : 16.694994744614895,
          "x" : 31.779779406873242,
          "y" : 33.92783717105263
        },
        {
          "height" : 1.2582236842105263,
          "width" : 14.974138848604996,
          "x" : 5.8793789332233466,
          "y" : 35.569490131578945
        },
        {
          "height" : 1.4473684210526316,
          "width" : 14.974138848604996,
          "x" : 5.8793789332233466,
          "y" : 35.437911184210527
        },
        {
          "height" : 1.2582236842105263,
          "width" : 0.90435032796264014,
          "x" : 20.909780338207316,
          "y" : 35.569490131578945
        },
        {
          "height" : 1.4473684210526316,
          "width" : 0.90435032796264014,
          "x" : 20.909780338207316,
          "y" : 35.437911184210527
        },
        {
          "height" : 1.2582236842105263,
          "width" : 26.6255770945038,
          "x" : 21.809182953925575,
          "y" : 35.569490131578945
        },
        {
          "height" : 1.4473684210526316,
          "width" : 26.6255770945038,
          "x" : 21.809182953925575,
          "y" : 35.437911184210527
        },
        {
          "height" : 1.2582236842105263,
          "width" : 42.490104575511232,
          "x" : 5.8793789332233466,
          "y" : 37.08984375
        },
        {
          "height" : 1.4473684210526316,
          "width" : 42.490104575511232,
          "x" : 5.8793789332233466,
          "y" : 36.958264802631582
        },
        {
          "height" : 1.2582236842105263,
          "width" : 42.372573542129558,
          "x" : 5.8793789332233466,
          "y" : 38.59991776315789
        },
        {
          "height" : 1.4473684210526316,
          "width" : 42.372573542129558,
          "x" : 5.8793789332233466,
          "y" : 38.468338815789473
        },
        {
          "height" : 1.2582236842105263,
          "width" : 42.408928832772311,
          "x" : 5.8793789332233466,
          "y" : 40.11924342105263
        },
        {
          "height" : 1.4473684210526316,
          "width" : 42.408928832772311,
          "x" : 5.8793789332233466,
          "y" : 39.987664473684212
        },
        {
          "height" : 1.2582236842105263,
          "width" : 42.489289658200398,
          "x" : 5.8793789332233466,
          "y" : 41.629317434210527
        },
        {
          "height" : 1.4473684210526316,
          "width" : 42.489289658200398,
          "x" : 5.8793789332233466,
          "y" : 41.49773848684211
        },
        {
          "height" : 1.2582236842105263,
          "width" : 42.493314351858011,
          "x" : 5.8793789332233466,
          "y" : 43.149671052631575
        },
        {
          "height" : 1.4473684210526316,
          "width" : 42.493314351858011,
          "x" : 5.8793789332233466,
          "y" : 43.018092105263158
        },
        {
          "height" : 1.4473684210526316,
          "width" : 22.499018773033889,
          "x" : 5.8793789332233466,
          "y" : 44.528166118421055
        }
      ],
      "text" : "Over time, both the course content and modes of delivery\nhave evolved to meet the varied needs of the learners. In the\n11th Edition, significant care and thought have been invested\nin recommendations that adapt or “$ex” care when resources\nor practice settings differ from the original recommendations.\nThis recognition of essential adaptability honors the continued\nadoption of ATLS in varied settings around the world. The\nprinciple of “Trauma Education for All” is implemented through\npartnerships and promulgation models designed to facilitate\nadoption of the course into nearly any area that seeks to improve\nits approach to the injured patient."
    },
    "file_id" : "8ef212cc-e16f-40c7-86c0-367472c468b3",
    "id" : "a5a088f1-df0d-47f2-bf8e-0aa84d740532",
    "is_favorite" : false,
    "page" : 4,
    "type" : "highlight",
    "updated_at" : "2026-01-12T20:12:18.778629+00:00",
    "user_id" : "2a632478-1ac8-4ac9-9ac4-c683dc50d9d0"
  }
]
   └─ Response: Status code: 200 Content-Length: 6263
Body:  [
  {
    "created_at" : "2026-01-12T20:06:14.172912+00:00",
    "data" : {
      "color" : "#fef08a",
      "isAiGenerated" : false,
      "rects" : [
        {
          "height" : 13.7400000000000... <truncated 179 chars>
[13:49:16.685] 🔍 [GeminiChatService] Chat oturumu başlatıldı
   └─ Mode: Legacy
[13:49:16.685] ℹ️ [PDFReaderVM] AI Chat hazır (PDF içeriği yüklendi)
[13:49:17.082] ℹ️ [PDFReaderVM] Okuma ilerlemesi yüklendi
   └─ Sayfa 3
[13:49:17.083] 🔍 [PDFReaderVM] Annotasyonlar yüklendi
   └─ 2 adet
[13:49:17.084] 🔍 [Supabase] Request: HEAD https://tftmypxwgccdgvldhaya.supabase.co/rest/v1/document_chunks?select=id&file_id=eq.8EF212CC-E16F-40C7-86C0-367472C468B3
Body: <none>
   └─ Request: HEAD https://tftmypxwgccdgvldhaya.supabase.co/rest/v1/document_chunks?select=id&file_id=eq.8EF212CC-E16F-40C7-86C0-367472C468B3
Body: <none>
context: ["requestID": FDE6256B-C498-4FCE-9159-E914DDC8BCEB]
[13:49:17.084] ℹ️ [ChatViewModel] Smart suggestions güncellendi: 4 öneri
[13:49:17.145] ℹ️ [ChatViewModel] Smart suggestions güncellendi: 4 öneri
[13:49:17.691] 🔍 [Supabase] Response: Status code: 200 Content-Length: -1
Body: 
   └─ Response: Status code: 200 Content-Length: -1
Body: 
context: ["requestID": FDE6256B-C498-4FCE-9159-E914DDC8BCEB]
[13:49:17.703] ℹ️ [PDFReaderVM] RAG modu aktif (önceden indexlenmiş)
[13:49:17.703] ℹ️ [PDFReaderVM] AI Chat hazır
[13:49:22.323] ℹ️ [ChatViewModel] Smart suggestions güncellendi: 4 öneri